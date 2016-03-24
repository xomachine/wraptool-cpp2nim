from mangler.base import finalize
from mangler.functions import function
from mangler.base import MangleInfo
import macros

proc mangle*(self: var MangleInfo, node:NimNode,
  templates:NimNode = newEmptyNode(), class: string = ""): string {.compileTime.} =
  # Mangles given proc description as C++ function name and returns it as a string
  # "ref" and "ptr" used in C++'s terms of "&" and "*"
  # Abscence of "var" considered as C++'s "const"
  # "string" will be considered as "std::string" 
  # "seq" will be considered as "std::vector"
  case node.kind:
  of nnkProcDef:
    finalize(function(self, node, templates, class))
  else:
    error("Unsupported node kind " & $node.kind)
    ""
  
when isMainModule:
  from mangler.tests import function_tests
  function_tests()