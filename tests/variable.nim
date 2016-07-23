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

    test "C++ name declaration":
      let d = newVariable(parseExpr(""""_a" as a: cint"""))
      check(d.name, "a")
      check(d.cppname, "_a")
      check(d.typename, "cint")
      require(d.namespace.len, 0)

    test "Namespaced declaration":
      let d = newVariable(parseExpr("""a: cint"""), "somenamespace")
      check(d.name, "a")
      check(d.cppname, "a")
      check(d.typename, "cint")
      require(d.namespace, "somenamespace")

  suite "Code generation":
    test "Simple declaration":
      let d = newVariable(parseExpr("a: cint")).generate_declaration()
      check(d.repr, "a* {.importcpp: \"a\".}: cint")

    test "C++ name declaration":
      let d = newVariable(parseExpr(""""_a" as a: cint""")).generate_declaration()
      check(d.repr, "a* {.importcpp: \"_a\".}: cint")

    test "Namespaced declaration":
      let d = newVariable(parseExpr("""a: cint"""), "somenamespace")
        .generate_declaration()
      check(d.repr, "a* {.importcpp: \"somenamespace::a\".}: cint")
