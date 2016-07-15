
import testtool
import macros
include declarations.class

static:
  suite "Class declaration parsing":
    test "Simple class declaration":
      let c = newClass(parseExpr("""someclass"""))
      check(c.name, "someclass")
      check(c.template_args.len, 0)
      check(c.cppname, "someclass")
      check(c.namespace, "")

    test "Class declaration with C++ name":
      let c = newClass(parseExpr(""""_cppclass" as someclass"""))
      check(c.name, "someclass")
      check(c.template_args.len, 0)
      check(c.cppname, "_cppclass")
      check(c.namespace, "")

    test "Template class declaration":
      let c = newClass(parseExpr("""someclass[T, G]"""))
      check(c.name, "someclass")
      check(c.template_args.len, 2)
      check(c.template_args[0].repr, "T")
      check(c.template_args[1].repr, "G")
      check(c.cppname, "someclass")
      check(c.namespace, "")

    test "Class declaration with namespace":
      let c = newClass(parseExpr("""someclass"""), "somenamespace")
      check(c.namespace, "somenamespace")
      check(c.name, "someclass")
      check(c.template_args.len, 0)
      check(c.cppname, "someclass")

  suite "Conversion to argument declaration":
    test "Simple class declaration":
      let c = newClass(parseExpr("""someclass"""))
      check(c.declaration_for_arglist().repr, "someclass")

    test "Class declaration with C++ name":
      let c = newClass(parseExpr(""""_cppclass" as someclass"""))
      check(c.declaration_for_arglist().repr, "someclass")

    test "Template class declaration":
      let c = newClass(parseExpr("""someclass[T, G]"""))
      check(c.declaration_for_arglist().repr, "someclass[T, G]")

    test "Class declaration with namespace":
      let c = newClass(parseExpr("""someclass"""), "somenamespace")
      check(c.declaration_for_arglist().repr, "someclass")

  when defined(cpp):
    suite "Type declaration":
      test "Simple class declaration":
        let c = newClass(parseExpr("""someclass"""))
        check(c.generate_type_declaration().repr, "someclass* {.importcpp: \"someclass\".} = object")

      test "Class declaration with C++ name":
        let c = newClass(parseExpr(""""_cppclass" as someclass"""))
        check(c.generate_type_declaration().repr, "someclass* {.importcpp: \"_cppclass\".} = object")

      test "Template class declaration":
        let c = newClass(parseExpr("""someclass[T, G]"""))
        check(c.generate_type_declaration().repr, "someclass* {.importcpp: \"someclass<\\'0>\".}[T, G] = object")

      test "Class declaration with namespace":
        let c = newClass(parseExpr("""someclass"""), "somenamespace")
        check(c.generate_type_declaration().repr, "someclass* {.importcpp: \"somenamespace::someclass\".} = object")

      test "Class with fields":
        let c = newClass(parseExpr("""someclass"""))
        let fields = newTree(nnkStmtList, parseExpr("a: cint"),
          parseExpr("b: cstring"), parseExpr(""""_special" as special: bool"""))
        let decl = c.generate_type_declaration(fields)
        check(decl.repr, "someclass* {.importcpp: \"someclass\".} = object\x0A" &
          "  a* {.importcpp: \"a\".}: cint\x0A" &
          "  b* {.importcpp: \"b\".}: cstring\x0A" &
          "  special* {.importcpp: \"_special\".}: bool\x0A")


