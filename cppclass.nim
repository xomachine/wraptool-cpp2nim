import macros
from sequtils import toSeq

type
  CppClass* = ref object
    cppname*: string
    name*: string
    template_args*: seq[NimNode]

proc newCppClass*(declaration: NimNode): CppClass =
  case declaration.kind
  of nnkBracketExpr:
    assert(declaration.len() > 1,
      "Small bracket expression passed as declaration of type: " & $declaration.len())
    declaration[0].expectKind(nnkIdent)
    result = newCppClass(declaration[0])
    result.template_args = toSeq(declaration.items)[1..<declaration.len]
  of nnkInfix:
    assert(declaration.len() == 3,
      "Broken infix node: " & declaration.treeRepr)
    declaration[0].expectKind(nnkIdent)
    declaration[1].expectKind(nnkStrLit)
    assert($declaration[0] == "as", "Unknown infix statement " &
      declaration.treeRepr)
    result = newCppClass(declaration[2])
    result.cppname = $declaration[1]
  of nnkIdent:
    new(result)
    result.name = $declaration
    result.cppname = result.name
    result.template_args = @[]
  else:
    error("Unknown node passed as type declaration: " & declaration.treeRepr)

proc declaration*(self: CppClass): NimNode =
  if self.template_args.len() > 0:
    result = newTree(nnkBracketExpr, newIdentNode(self.name))
    for arg in self.template_args:
      result.add(arg)
  else: result = newIdentNode(self.name)
