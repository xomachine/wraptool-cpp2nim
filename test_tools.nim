
template test*[T](code:expr, answer: T) = 
    let ii = instantiationInfo()
    let position = "$1($2, 1)" % [ii.filename, $ii.line]
    let test_result = (code)
    if test_result != answer:
      warning("\n$3Expected: $1\n$3Got: $2" %
        [$answer, test_result, position])