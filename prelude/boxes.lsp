;;;; Mutable single-element boxes

($provide! (box box? unbox set-box!)
  ($declare-record! box (val))
  ($define! unbox box-val)
  ($define! set-box! set-box-val!))
