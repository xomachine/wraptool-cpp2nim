from types import mangle_type, mangle_typename
from base import MangleInfo
from base import mangle_ident
import macros

   
proc mangle_operator(sign: string, unary: bool = false): string {.compileTime.} =
  case sign:
    of "new": "nw"
    of "new[]": "na"
    of "delete": "dl"
    of "delete[]": "da"
    of "~": "co"
    of "+":
      if unary: "ps"
      else: "pl"
    of "-":
      if unary: "ng"
      else: "mi"
    of "*":
      if unary: "de"
      else: "ml"
    of "/": "dv"
    of "%": "rm"
    of "&":
      if unary: "ad"
      else: "an"
    of "|": "or"
    of "^": "eo"
    of "=": "aS"
    of "+=": "pL"
    of "-=": "mI"
    of "*=": "mL"
    of "/=": "dV"
    of "%=": "rM"
    of "&=": "aN"
    of "|=": "oR"
    of "^=": "eO"
    of "<<": "ls"
    of ">>": "rs"
    of "<<=": "lS"
    of ">>=": "rS"
    of "==": "eq"
    of "!=": "ne"
    of "<": "lt"
    of ">": "gt"
    of "<=": "le"
    of ">=": "ge"
    of "!": "nt"
    of "&&": "aa"
    of "||": "oo"
    of "++": "pp"
    of "--": "mm"
    of ",": "cm"
    of "->*": "pm"
    of "->": "pt"
    of "()": "cl"
    of "[]": "ix"
    of "?": "qu"
    else: sign 

proc mangle_function_name(node:NimNode, unary: bool = false): string {.compileTime.} =
  case node.kind:
    of nnkIdent: # function name
      mangle_ident($node)
    of nnkAccQuoted: # operator
      mangle_operator($node[0], unary)
    of nnkPostfix: # name with asteriks
      mangle_function_name(node[1])
    else:
      error("Unknown kind of function name: " & $node.kind)
      ""

  
proc function*(self: var MangleInfo, function:NimNode,
  templates:NimNode = newEmptyNode(), class: string = ""): string  =
  result = ""
  expectKind(function, nnkProcDef)
  let arguments = function[3] # nnkFormalParams
  var mangled_templates = ""
  for t in templates.children():
    mangled_templates &= mangle_type(self, t)
  if mangled_templates != "":
    mangled_templates = "I" & mangled_templates & "E"
  let mangled_func = mangle_function_name(function[0], arguments.len() < 3)
  result = mangle_typename(self, class, mangled_func &  mangled_templates )
  for arg in arguments.children():
    if arg.kind == nnkIdentDefs:
      result &= mangle_type(self, arg[1])
  if arguments.len() < 2:
    result &= mangle_type(self, newEmptyNode())
