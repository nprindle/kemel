- Move more things out of the builtins:
  - `progn`
  - `append` (currently needed for splice syntax, probably write `$lambda` etc. without splices to begin with until `append` is implemented)
- Re-implement control flow (like `tagbody`, `block`, etc.) in terms of delimited continuations
- Re-implement exceptions in terms of delimited continuations
- Tail call optimization if possible
- numbers
  - promotion rules
  - ratios, floats
  - complex numbers
- arrays, vectors
- data types: