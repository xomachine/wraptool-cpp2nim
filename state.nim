from cppclass import CppClass
from macros import error, newIdentNode, newStrLitNode, newTree, `$`, kind
from macros import nnkExprColonExpr, nnkStrLit

type
  SourceType* {.pure.} = enum
    none, dynlib, header
  WrapSource = object
    is_string: bool
    case kind: SourceType
    of SourceType.none: discard
    of SourceType.dynlib, SourceType.header:
      file*: string
  
  State* = object
    namespace*: string
    class*: CppClass
    source: WrapSource

proc newState*(source: NimNode = newIdentNode(""),
  source_type: SourceType = SourceType.none): State = 
  if source_type == SourceType.none or
    $source == "": State()
  else: 
    let source_string = $source
    State(source: WrapSource(
      is_string: source.kind == nnkStrLit,
      kind: source_type,
      file: source_string))
    
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
    let file = 
      if self.source.is_string:
        newStrLitNode(self.source.file)
      else: newIdentNode(self.source.file)
    newTree(nnkExprColonExpr,
      newIdentNode($self.source.kind),
      file)
