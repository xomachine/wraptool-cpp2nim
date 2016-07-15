import testtool
import macros
include declarations.variable

static:
  suite "Variable declaration parsing":
    test "Simple declaration":
      let d = newVariable(parseExpr("a: cint"))
      check(d.name, "a")
      check(d.cppname, "a")
      check(d.typename, "cint")
      require(d.namespace.len, 0)
