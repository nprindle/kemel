($provide! ($loop $while $do-while $while-then $for)
  ($define! make-label
    ($lambda ()
      ($let/cc k
        ($letrec
          ((f ($lambda () (apply-continuation k (list f)))))
          f))))

  ($define! arg-or-inert
    ($lambda (args)
      ($if (null? args)
        #inert
        ($sequence
          ($the null (cdr args))
          (car args)))))

  ($define! $loop
    ($macro body
      ($let ((break-cont-name (gensym))
             (loop-start-label-name (gensym)))
        (list $let/cc break-cont-name
              (list
                $let
                (list (list ($quote break)
                            (list $lambda ($quote args)
                                  (list apply-continuation break-cont-name
                                        (list list (list arg-or-inert ($quote args)))))))
                (list $define! loop-start-label-name (list make-label))
                (cons $sequence body)
                (list loop-start-label-name))))))

  ($define! $do-while
    ($macro (cond . body)
      ($let ((break-cont-name (gensym))
             (loop-start-label-name (gensym)))
        (list $let/cc break-cont-name
              (list
                $let
                (list (list ($quote break)
                            (list $lambda ($quote args)
                                  (list apply-continuation break-cont-name
                                        (list list (list arg-or-inert ($quote args)))))))
                (list $define! loop-start-label-name (list make-label))
                (cons $sequence body)
                (list $when cond (list loop-start-label-name)))))))

  ($define! $while
    ($macro (cond . body)
      ($let ((break-cont-name (gensym))
             (loop-start-label-name (gensym)))
        (list $let/cc break-cont-name
              (list
                $let
                (list (list ($quote break)
                            (list $lambda ($quote args)
                                  (list apply-continuation break-cont-name
                                        (list list (list arg-or-inert ($quote args)))))))
                (list $define! loop-start-label-name (list make-label))
                (list $when (list not? cond) (list apply-continuation break-cont-name (list list #inert)))
                (list* $let (list (list ($quote continue) loop-start-label-name)) body)
                (list loop-start-label-name))))))

  ;; It is tempting to say that `for(INIT; COND; OP) { BODY }` is equivalent to
  ;; `{ INIT; while (COND) { BODY OP; } }`, but in reality, `continue` in the
  ;; former will still execute `OP`, unlike in the latter.
  ($define! $while-then
    ($macro (cond final . body)
      ($let ((break-cont-name (gensym))
             (continue-cont-name (gensym))
             (loop-start-label-name (gensym)))
        (list $let/cc break-cont-name
              (list
                $let
                (list (list ($quote break)
                            (list $lambda ($quote args)
                                  (list apply-continuation break-cont-name
                                        (list list (list arg-or-inert ($quote args)))))))
                (list $define! loop-start-label-name (list make-label))
                (list $when (list not? cond) (list apply-continuation break-cont-name (list list #inert)))
                (list $let/cc continue-cont-name
                      (list* $let
                             (list (list ($quote continue)
                                         (list $lambda (list) (list apply-continuation continue-cont-name (list list #inert)))))
                             body))
                final
                (list loop-start-label-name))))))

  ($define! $for
    ($macro (binder iter . body)
      ($the symbol binder)
      ($let ((break-cont-name (gensym))
             (iterator-name (gensym))
             (loop-start-label-name (gensym)))
        (list $let/cc break-cont-name
              (list
                $let
                (list (list ($quote break)
                            (list $lambda ($quote args)
                                  (list apply-continuation break-cont-name
                                        (list list (list arg-or-inert ($quote args)))))))
                (list $define! iterator-name iter)
                (list $the (list ($quote or) ($quote applicative) ($quote list)) iterator-name)
                (list $define! iterator-name (list $if (list list? iterator-name) (list list->iter iterator-name) iterator-name))
                (list $define! loop-start-label-name (list make-label))
                (list $define! binder (list next iterator-name))
                (list $when (list equal? binder :done) (list apply-continuation break-cont-name (list list #inert)))
                (list* $let (list (list ($quote continue) loop-start-label-name)) body)
                (list loop-start-label-name)))))))
