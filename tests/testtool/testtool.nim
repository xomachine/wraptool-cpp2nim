import macros
#from terminal import cursorUp, cursorForward, setForegroundColor
from terminal import resetAttributes, ForegroundColor, eraseLine
from strutils import `%`

type
  Status {.pure.} = enum
    ok, failed, fatal, unknown

static:
  var teststatus: Status
  var errors: int
  var oks: int

proc colored_echo(text: string, color: ForegroundColor) {.compileTime.} =
  #setForegroundColor(color)
  echo text
  #resetAttributes()

proc check*(cond: bool){.compileTime.} =
  if cond:
    teststatus = Status.ok
  else:
    teststatus = Status.failed

proc require*(cond: bool){.compileTime.} =
  if cond:
    teststatus = Status.ok
  else:
    teststatus = Status.fatal

template suite*(name: string, code: untyped) =
  echo "Started test suite $1" % name
  errors = 0
  oks = 0
  (code)
  echo "Test suite $1 completed with $2 failed and $3 successful tasks" %
    [name, $errors, $oks]


template test*(name: string, code: untyped) =
  let notification = "Testing $1 ..." % name
  echo notification
  #cursorUp()
  #cursorForward(notification.len)
  teststatus = Status.unknown
  (code)
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


static:
  suite "TestTool":
    test "test template":
      assert(true)
    test "check":
      check(true)
    test "false check":
      check(false)
    test "require":
      require(true)
