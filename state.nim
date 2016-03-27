from cppclass import CppClass
from macros import error, newIdentNode, newStrLitNode, newTree
from macros import nnkExprColonExpr

type
  SourceType = enum
    none, dynlib, header
  WrapSource = object
    case kind: SourceType
    of none: discard
    of dynlib, header:
      file*: string
  
  State* = object
    namespace*: string
    class*: CppClass
    source: WrapSource

proc append*(self: State, namespace: string = nil,
  class: CppClass = nil): State =
  result = self
  if class != nil:
    if result.class == nil: result.class = class
    else: error(
      "Class can not be appended becouse it already exists in State!")
  if namespace != nil:
    result.namespace =
      if result.namespace != nil:
        result.namespace & "::" & namespace
      else: namespace

proc source_declaration*(self: State): NimNode =
  case self.source.kind
  of none: newIdentNode("nodecl")
  of dynlib, header:
    newTree(nnkExprColonExpr,
      newIdentNode($self.source.kind),
      newStrLitNode(self.source.file))
