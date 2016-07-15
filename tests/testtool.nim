import macros
#from terminal import cursorUp, cursorForward, setForegroundColor
from terminal import resetAttributes, ForegroundColor, eraseLine
from strutils import `%`

type
  Status* {.pure.} = enum
    ok, failed, fatal, unknown

  TestFailed = object of Exception
  TestCrushed = object of Exception





proc colored_echo(text: string, color: ForegroundColor) {.compileTime.} =
  #setForegroundColor(color)
  echo text
  #resetAttributes()


template internal_suite(name: string, code: untyped) {.dirty.} =
  var errors: int = 0
  var oks: int = 0
  var teststatus: Status
  echo "Started test suite \"" & name & "\""
  (code)
  echo "Test suite \"" & name & "\" completed with " & $errors &
    " failed and " & $oks & " successful tasks"

template suite*(name: string, code: untyped) =
  block:
    internal_suite(name):
      (code)

template test*(name: string, code: untyped)  =

  echo "Testing $1 ..." % name
  #cursorUp()
  #cursorForward(notification.len)
  teststatus = Status.unknown
  try:
    (code)
  except TestFailed:
    teststatus = Status.failed
  except TestCrushed:
    teststatus = Status.fatal
  case teststatus
  of Status.ok:
    colored_echo("[  OK  ]", fgGreen)
    oks.inc
  of Status.failed:
    colored_echo("[ FAIL ]", fgYellow)
    errors.inc
  of Status.fatal:
    colored_echo("[ FAIL ]", fgRed)
    error("Failed to complete tests due to critical test failure!")
  of Status.unknown:
    #eraseLine()
    warning("""You have not written test for $1!
Consider adding "check" or "require" procedure under test statement""" % name)


template check*(cond: bool) =
  teststatus = Status.ok
  if not cond:
    raise newException(TestFailed, "")

template require*(cond: bool) =
  teststatus = Status.ok
  if not cond:
    raise newException(TestCrushed, "")

when isMainModule:
  static:
    suite "TestTool":
      test "abscence of \"check\" or \"require\". This test should throw warning":
        assert(true)
      test "checking mechanism":
        check(true)
      test "check failure. This test should fail":
        check(false)
      test "require mechanism":
        require(true)
