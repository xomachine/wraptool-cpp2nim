from state import State, source_declaration
import macros

## Vars, consts and other imported values handler

proc generate_var_pragma(state: State, cppname: string): NimNode =
  let namespace_prefix =
    if state.namespace != nil and state.class == nil:
      state.namespace & "::"
    else: ""
  let importcpp = newTree(nnkExprColonExpr,
    newIdentNode("importcpp"),
    newStrLitNode(namespace_prefix & cppname))
  newTree(nnkPragma, importcpp, state.source_declaration)

proc generate_var*(state: State, declaration: NimNode): NimNode =
  let varinfo = case declaration.kind
    of nnkInfix:
      assert(declaration.len == 4, "Broken infix: " & declaration.treeRepr)
      declaration[0].expectKind(nnkIdent)
      declaration[2].expectKind(nnkIdent)
      declaration[1].expectKind(nnkStrLit)
      declaration[3].expectKind(nnkStmtList)
      assert($declaration[0] == "as", """Only "<cppname>" as <nimname> """ &
        """declarations allowed, not """ & declaration.repr)
      assert(declaration[3].len == 1, "Broken declaration: " & declaration.repr)
      let cppname = $declaration[1]
      let nimname = $declaration[2]
      let typename = $declaration[3][0]
      (cppname: cppname, nimname: nimname, typename: typename)
    of nnkCall:
      assert(declaration.len == 2, "Broken declaration: " & declaration.repr)
      declaration[0].expectKind(nnkIdent)
      declaration[1].expectKind(nnkStmtList)
      assert(declaration[1].len == 1, "Broken declaration: " & declaration.repr)
      let cppname = $declaration[0]
      let nimname = $declaration[0]
      let typename = $declaration[1][0]
      (cppname: cppname, nimname: nimname, typename: typename)
    else:
      error("Unknown NimNode: " & declaration.treeRepr)
      ("", "", "")
  
  let pragma = newTree(nnkPragmaExpr,
    newIdentNode(varinfo.nimname).postfix("*"),
    (if state.class == nil:
      state.generate_var_pragma(varinfo.cppname) else: newEmptyNode()))
  newTree(nnkIdentDefs, pragma, newIdentNode(varinfo.typename), newEmptyNode())

  
when isMainModule:
  from test_tools import test
  proc n(e: string): NimNode {.compileTime.} = parseExpr(e)
  
  static:
    let es = State()
    test(es.generate_var(n"""simplevar: int"""),
      n"""var simplevar*{.importcpp:"simplevar", nodecl.}: int"""[0])