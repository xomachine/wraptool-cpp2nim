import macros
from terminal import ForegroundColor
from strutils import `%`

type
  TestFailed = object of Exception
  TestCrushed = object of Exception


# Terminal managing code (linux only)
when not defined(windows):
  const resetAttributes = "\e[0m"
  proc cursorUp(lines: int = 1): string =
    "\e[" & $lines & 'A'
  proc colorize(color: ForegroundColor, bright: bool = false): string =
    "\e[" & $(ord(color) + (if bright: 60 else: 0)) & 'm'
else:
  const resetAttributes = ""
  proc cursorUp(lines: int = 1): string =
    ""
  proc colorize(color: ForegroundColor, bright: bool = false): string =
    ""

proc colored_echo(text: string, color: ForegroundColor,
  bright: bool = false) {.compileTime.} =
  echo cursorUp() & colorize(color, bright) & text & resetAttributes




template internal_suite(name: string, code: untyped) {.dirty.} =
  var errors: int = 0
  var oks: int = 0
  var is_checked: bool
  echo "Started test suite \"" & name & "\""
  (code)


template suite*(name: string, code: untyped) =
  block:
    internal_suite(name):
      (code)
    echo "Completed with " &
      colorize(fgYellow, true) &
      $errors & resetAttributes &
      " failed and " & colorize(fgGreen, true) & $oks &
      resetAttributes & " successful tasks"

template test*(name: string, code: untyped)  =

  echo "Testing $1 ..." % name
  is_checked = false
  try:
    (code)
    if is_checked:
      colored_echo("[  OK  ]", fgGreen)
      oks.inc
    else:
      #eraseLine()
      warning("""You have not written test for $1!
Consider adding "check" or "require" procedure under test statement""" % name)
  except TestFailed:
    colored_echo("[ FAIL ]", fgYellow, true)
    errors.inc
    echo getCurrentExceptionMsg()
  except TestCrushed:
    colored_echo("[ FAIL ]", fgRed, true)
    echo getCurrentExceptionMsg()
    error("Failed to complete tests due to critical test failure!")


template check(ex1: untyped, ex2: untyped, ex: typedesc) =
  is_checked = true
  let result1 = (ex1)
  let result2 = (ex2)
  if result1 != result2:
    raise newException(ex, "$1 == $2" % [result1.repr, result2.repr])

template check*(ex1: untyped, ex2: untyped) =
  check(ex1, ex2, TestFailed)

template require*(ex1: untyped, ex2: untyped) =
  check(ex1, ex2, TestCrushed)


when isMainModule:
  static:
    suite "TestTool":
      test "abscence of \"check\" or \"require\". This test should throw warning":
        assert(true)
      test "checking mechanism":
        check(true, true)
      test "check failure. This test should fail":
        check(false, true)
      test "require mechanism":
        require(true, true)
    suite "Multiple suites":
      test "another test in next suite":
        check(true, true)
