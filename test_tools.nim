
template test*[T](code:expr, answer: T) = 
  from strutils import `%`
  from macros import warning
  let ii = instantiationInfo()
  let position = "$1($2, 1)" % [ii.filename, $ii.line]
  let test_result = (code)
  if test_result != answer:
    warning("\n$3 Warning: Test failed!\n$3 Expected: $1\n$3 Got:      $2" %
      [answer.repr, test_result.repr, position])