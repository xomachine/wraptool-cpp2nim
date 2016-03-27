from cppclass import CppClass

type
  SourceType* = enum
    none, dynlib, header
  WrapSource* = object
    case kind*: SourceType
    of none: discard
    of dynlib, header:
      file*: string
  
  State* = object
    namespace*: string
    class*: CppClass
    source*: WrapSource
