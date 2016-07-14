
import macros
from sequtils import toSeq, filter, map, repeat, concat
from declarations.variable import newVariable, generate_declaration

type
  Class* = ref object
    ## Representing C++ class
    namespace: string
    cppname: string
    name: string
    template_args: seq[NimNode]

proc newClass*(declaration: NimNode, namespace: string = ""): Class =
  ## Creates new Class from class declaration in Nim
  ## `declaration` - AST with class declaration
  case declaration.kind
  of nnkBracketExpr:
    assert(declaration.len() > 1,
      "Small bracket expression passed as declaration of type: " & $declaration.len())
    declaration[0].expectKind(nnkIdent)
    result = newClass(declaration[0])
    result.template_args = toSeq(declaration.items)[1..<declaration.len]
  of nnkInfix:
    assert(declaration.len() == 3,
      "Broken infix node: " & declaration.treeRepr)
    declaration[0].expectKind(nnkIdent)
    declaration[1].expectKind(nnkStrLit)
    assert($declaration[0] == "as", "Unknown infix statement " &
      declaration.treeRepr)
    result = newClass(declaration[2])
    result.cppname = $declaration[1]
  of nnkIdent:
    new(result)
    result.name = $declaration
    result.cppname = result.name
    result.template_args = @[]
  else:
    error("Unknown node passed as type declaration: " & declaration.treeRepr)
  result.namespace = namespace

proc declaration_for_arglist*(self: Class): NimNode =
  ## Returns Nim declaration for given Class
  ## to use it in proc argument list
  if self.template_args.len() > 0:
    result = newTree(nnkBracketExpr, newIdentNode(self.name))
    for arg in self.template_args:
      result.add(arg)
  else: result = newIdentNode(self.name)

when defined(cpp):
  proc generate_type_pragma(self: Class): NimNode =
    ## Generates "importcpp" pragma
    ## for type declaration
    let namespace_prefix =
      if self.namespace.len > 0 : self.namespace & "::"
      else: ""
    let template_params =
      if self.template_args.len > 0: "<'0>"
      else: ""
    let import_string = namespace_prefix & self.cppname & template_params
    let importcpp = newTree(nnkExprColonExpr,
      newIdentNode("importcpp"),
      newStrLitNode(import_string))
    newTree(nnkPragma, importcpp )#TODO state.sourcedeclaration alternative)

  proc generate_type_declaration*(self: Class, fields: NimNode = newStmtList()): NimNode =
    ## Generates type declaration for current class
    ## Returned declaration must be placed into TypeSection node
    ## Given state must include class field with current CppClass
    ## `fields` - class fields to place into declaration
    fields.expectKind(nnkStmtList)
    let class_fields = toSeq(fields.children())
      .filter(proc (i: NimNode): bool =
        (i.kind == nnkCall or (i.kind == nnkInfix and $i[0] == "as")))
      .map(proc (i:NimNode): NimNode = newVariable(i).generate_declaration())
    let reclist = if class_fields.len > 0 : newTree(nnkRecList, class_fields)
      else: newEmptyNode()
    let emptyobject = newTree(nnkObjectTy, repeat(newEmptyNode(), 2).concat(@[reclist]))
    let pragmaexpr = newTree(nnkPragmaExpr,
      newIdentNode(self.name).postfix("*"),
      self.generate_type_pragma)
    let generics =
      if self.template_args.len > 0:
        newTree(nnkGenericParams,
          newTree(nnkIdentDefs,
            self.template_args.concat(repeat(newEmptyNode(), 2))
            )
          )
      else: newEmptyNode()
    newTree(nnkTypeDef, pragmaexpr, generics, emptyobject)
