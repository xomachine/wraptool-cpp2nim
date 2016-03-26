import macros
from sequtils import toSeq

type
  CppClass* = ref object
    cppname*: string
    name*: string
    template_args*: seq[NimNode]

proc new*[T: CppClass](declaration: NimNode, cppname: string = ""): T =
  new(result)
  case declaration.kind
  of nnkBracketExpr:
    assert(declaration.len() > 1,
      "Small bracket expression passed as declaration of type: " & $declaration.len())
    declaration[0].expectKind(nnkIdent)
    result.name = $declaration[0]
    result.template_args = toSeq(declaration.children())
    result.template_args.delete(0)
  of nnkIdent:
    result.name = $declaration
    result.template_args = @[]
  else:
    error("Unknown node passed as type declaration: " & declaration.treeRepr)
  result.cppname =
    if cppname == "": result.name
    else: cppname

proc declaration*(self: CppClass): NimNode =
  if self.template_args.len() > 0:
    result = newTree(nnkBracketExpr, newIdentNode(self.name))
    for arg in self.template_args:
      result.add(arg)
  else: result = newIdentNode(self.name)
