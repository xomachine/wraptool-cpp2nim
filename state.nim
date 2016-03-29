from cppclass import CppClass
from macros import error, newIdentNode, newStrLitNode, newTree
from macros import nnkExprColonExpr

type
  SourceType* {.pure.} = enum
    none, dynlib, header
  WrapSource = object
    case kind: SourceType
    of SourceType.none: discard
    of SourceType.dynlib, SourceType.header:
      file*: string
  
  State* = object
    namespace*: string
    class*: CppClass
    source: WrapSource

proc newState*(source: string = "",
  source_type: SourceType = SourceType.none): State = 
  if source_type == SourceType.none: State()
  else: State(source: WrapSource(kind: source_type, file: source))
    
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
  of SourceType.none: newIdentNode("nodecl")
  of SourceType.dynlib, SourceType.header:
    newTree(nnkExprColonExpr,
      newIdentNode($self.source.kind),
      newStrLitNode(self.source.file))
