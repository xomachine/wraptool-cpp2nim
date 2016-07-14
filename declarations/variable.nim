## Here all variables, constants and class field related things
import macros

type
  Variable* = ref object
    ## Stores all information about variable
    namespace: string
    name: string
    typename: string
    cppname: string


## Vars, consts and other imported values handler



proc newVariable*(declaration: NimNode, namespace: string = ""): Variable =
  ## Parses given NimNode with variable declaration in pseudo-Nim language
  ## and creates new Variable object
  new(result)
  case declaration.kind
  of nnkInfix:
    assert(declaration.len == 4, "Broken infix: " & declaration.treeRepr)
    declaration[0].expectKind(nnkIdent)
    declaration[2].expectKind(nnkIdent)
    declaration[1].expectKind(nnkStrLit)
    declaration[3].expectKind(nnkStmtList)
    assert($declaration[0] == "as", """Only "<cppname>" as <nimname> """ &
      """declarations allowed, not """ & declaration.repr)
    assert(declaration[3].len == 1, "Broken declaration: " & declaration.repr)
    result.cppname = $declaration[1]
    result.name = $declaration[2]
    result.typename = $declaration[3][0]
  of nnkCall:
    assert(declaration.len == 2, "Broken declaration: " & declaration.repr)
    declaration[0].expectKind(nnkIdent)
    declaration[1].expectKind(nnkStmtList)
    assert(declaration[1].len == 1, "Broken declaration: " & declaration.repr)
    result.cppname = $declaration[0]
    result.name = $declaration[0]
    result.typename = $declaration[1][0]
  else:
    error("Unknown NimNode: " & declaration.treeRepr)
    result.namespace = namespace

when declared(cpp):
  proc generate_var_pragma(self: Variable): NimNode =
    let namespace_prefix =
      if self.namespace.len > 0:
        self.namespace & "::"
      else: ""
    let importcpp = newTree(nnkExprColonExpr,
      newIdentNode("importcpp"),
      newStrLitNode(namespace_prefix & self.cppname))
    newTree(nnkPragma, importcpp)
else:
  {.fatal: "Not implemented yet".}

proc generate_declaration*(self: Variable): NimNode =
  let pragma = newTree(nnkPragmaExpr,
    newIdentNode(self.name).postfix("*"),
    state.generate_var_pragma(self.cppname))
  newTree(nnkIdentDefs, pragma, newIdentNode(self.typename), newEmptyNode())
