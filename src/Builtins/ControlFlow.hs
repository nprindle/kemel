{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE TupleSections #-}

module Builtins.ControlFlow (builtinControlFlow) where

import Control.Monad.Reader (ask)
import TextShow (TextShow(..))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Vector (Vector)
import Data.Vector qualified as Vector
import Control.Monad.Except (catchError, throwError)
import Data.Foldable (foldlM)

import Errors
import Core (eval, progn, nil, mkBindings)
import Types
import Builtins.Utils (builtinApp, builtinOp, Builtin)

builtinControlFlow :: [(Symbol, Expr)]
builtinControlFlow = builtinConditionals ++ builtinControlStructures

builtinConditionals :: [(Symbol, Expr)]
builtinConditionals =
  [ ("if", builtinOp primIf)
  , ("and", builtinOp primAnd)
  , ("or", builtinOp primOr)
  , ("not", builtinApp primNot)
  , ("when", builtinOp primWhen)
  , ("unless", builtinOp primUnless)
  ]

builtinControlStructures :: [(Symbol, Expr)]
builtinControlStructures =
  [ ("progn", builtinOp primProgn)
  , ("let", builtinOp primLet)
  , ("block", builtinOp primBlock)
  , ("return-from", builtinOp primReturnFrom)
  , ("tagbody", builtinOp primTagbody)
  , ("go", builtinOp primGo)
  ]

truthy :: Expr -> Bool
truthy = \case
  LBool b -> b
  _ -> True

condition :: Environment -> Expr -> Eval Bool
condition env cond = truthy <$> eval env cond

primIf :: Builtin
primIf args = do
  env <- ask
  case args of
    [cond, x, y] -> do
      cond' <- condition env cond
      if cond' then eval env x else eval env y
    _ -> numArgs "if" 3 args

primAnd :: Builtin
primAnd args = do
  env <- ask
  let
    go [] = pure $ LBool True
    go [x] = eval env x
    go (x:xs) = do
      x' <- condition env x
      if x' then go xs else pure $ LBool False
  go args

primOr :: Builtin
primOr args = do
  env <- ask
  let
    go [] = pure $ LBool False
    go [x] = eval env x
    go (x:xs) = do
      x' <- eval env x
      if truthy x' then pure x' else go xs
  go args

primNot :: Builtin
primNot [LBool x] = pure $ LBool $ not x
primNot [x] = evalError $ "not: expected bool, but got " <> showt x
primNot args = numArgs "not" 1 args

primWhen :: Builtin
primWhen (cond:body) = do
  env <- ask
  cond' <- condition env cond
  if cond' then progn env body else pure nil
primWhen args = numArgsAtLeast "when" 1 args

primUnless :: Builtin
primUnless (cond:body) = do
  env <- ask
  cond' <- condition env cond
  if not cond' then progn env body else pure nil
primUnless args = numArgsAtLeast "unless" 1 args

letBody :: Symbol -> [Expr] -> Eval ([Expr], [Expr])
letBody name []              = numArgs name 1 []
letBody _    (LList xs:body) = pure (xs, body)
letBody name (_:_)           = evalError $ showt name <> ": invalid bindings"

primLet :: Builtin
primLet args = do
  (xs, body) <- letBody "let" args
  env <- ask
  let
    getBinding (LList [LSymbol name, val]) = (name,) <$> eval env val
    getBinding (LSymbol name) = pure (name, nil)
    getBinding _ = evalError "let: invalid variable specification"
  binds <- mkBindings =<< traverse getBinding xs
  withLocalBindings binds $ do
    env' <- ask
    progn env' body

primProgn :: Builtin
primProgn body = ask >>= \env -> progn env body

primBlock :: Builtin
primBlock = \case
    (LSymbol blockName:body) -> do env <- ask; block blockName $ progn env body
    (LList []:body)          -> do env <- ask; block "nil" $ progn env body
    (_:_)                    -> evalError "block: expected symbol as block name"
    args                     -> numArgsAtLeast "block" 1 args
  where
    block :: Symbol -> Eval Expr -> Eval Expr
    block blockName a =
      a `catchError` \case
        ReturnFrom target val
          | blockName == target -> pure val
          -- NOTE: non-matching block names should bubble up
        e -> throwError e

primReturnFrom :: Builtin
primReturnFrom = \case
  [LSymbol blockName] -> do
    throwError $ ReturnFrom blockName nil
  [LSymbol blockName, val] -> do
    env <- ask
    throwError . ReturnFrom blockName =<< eval env val
  [LList []] -> do
    throwError $ ReturnFrom "nil" nil
  [LList [], val] -> do
    env <- ask
    throwError . ReturnFrom "nil" =<< eval env val
  [_]    -> evalError "return-from: expected symbol for block name"
  [_, _] -> evalError "return-from: expected symbol for block name"
  args   -> numArgsBound "return-from" (1, 2) args

primTagbody :: Builtin
primTagbody args = do
  (table, exprs) <- buildTagTable args
  env <- ask
  let
    len = Vector.length exprs
    runAt !ix =
      if ix < 0 || ix >= len
      then pure ()
      else eval env (exprs Vector.! ix) *> runAt (ix + 1)
    go !ix =
      runAt ix `catchError` \case
        TagGo tagName
          | Just ix' <- table Map.!? tagName -> go ix'
        e -> throwError e
  go 0
  pure nil
  where
    buildTagTable :: [Expr] -> Eval (Map TagName Int, Vector Expr)
    buildTagTable = fmap collect . foldlM go (0, mempty, mempty)
      where
        collect (_, tagTable, exprs) = (tagTable, Vector.fromList (reverse exprs))
        go :: (Int, Map TagName Int, [Expr]) -> Expr -> Eval (Int, Map TagName Int, [Expr])
        go (i, tagTable, exprs) = \case
          -- normal symbols
          LSymbol sym -> pure (i, Map.insert (TagSymbol sym) i tagTable, exprs)
          LKeyword b -> pure (i, Map.insert (TagKeyword b) i tagTable, exprs)
          LInt n -> pure (i, Map.insert (TagInt n) i tagTable, exprs)
          -- NIL symbol
          LList [] -> pure (i, Map.insert (TagSymbol "nil") i tagTable, exprs)
          -- lists
          l@(LList _) -> pure (i + 1, tagTable, l:exprs)
          l@(LDottedList _ _) -> pure (i + 1, tagTable, l:exprs)
          e -> evalError $ "tagbody: invalid tag or form type: " <> renderType e

primGo :: Builtin
primGo = \case
  [LSymbol sym] -> throwError $ TagGo $ TagSymbol sym
  [LKeyword b]  -> throwError $ TagGo $ TagKeyword b
  [LInt n]      -> throwError $ TagGo $ TagInt n
  [LList []]    -> throwError $ TagGo $ TagSymbol "nil"
  [e]           -> evalError $ "go: invalid tag type: " <> renderType e
  args          -> numArgs "go" 1 args