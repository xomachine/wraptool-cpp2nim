import macros
from strutils import `%`, join
from sequtils import filter
from base import mangle_ident, enclose_if, substitute, remember
from base import unwind_infixes, mark_last_as_nested, new, enclose
from base import MangleInfo


# The name mangler for C++ Itanium mangler style








proc mangle_typename*(self: var MangleInfo, input:string,
  forced_name: string = ""): string {.compileTime.} =
  case input:
  of "wchar_t": "w"
  of "bool": "b"
  of "char", "cchar": "c"
  of "cschar", "int8": "a"
  of "cuchar": "h"
  of "cshort", "int16": "s"
  of "cushort", "uint16": "t"
  of "cint", "int32": "i"
  of "cuint", "uint32": "j"
  of "clong": "l"
  of "culong": "m"
  of "clonglong", "int64": "x"
  of "culonglong","uint64": "y"
  of "int128": "n"
  of "uint128": "o"
  of "cfloat", "float32": "f"
  of "cdouble", "float64": "d"
  of "clongdouble", "BiggestFloat": "e"
  of "std::nullptr_t", "typeof(nil)": "Dn"
  of "auto": "Da"
  of "float128": "g"
  of "ellipsis": "z"
  #of "IEEE 754r decimal floating point (64 bits)": "Dd"
  #of "IEEE 754r decimal floating point (128 bits)": "De"
  #of "IEEE 754r decimal floating point (32 bits)": "Df"
  #of "IEEE 754r half-precision floating point (16 bits)": "Dh"
  of "char32_t": "Di"
  of "char16_t": "Ds"
  of "decltype(auto)": "Dc"
  of "void": "v" # Actually it never happens
  else:
    if input != "":
      let nim_repr = "\"$1\" > $2" % [self.namespace, input]
    
      let sub_repr = parseExpr(nim_repr).lispRepr()
      #hint sub_repr
      let mi = self.substitute(sub_repr)
      if mi != "":
        return mi
      else:
        self.remember(sub_repr)
    let mangled_name = enclose(self, mangle_ident($input), forced_name)
    if mangled_name[0] == 'N' and input != "":
      self.mark_last_as_nested()
    mangled_name


proc mangle_type*(self: var MangleInfo, input: NimNode,
  still_const: bool = true): string {.compileTime.} =
  result = ""
  if still_const:
    result = "K"
  let sub = self.substitute(input.lispRepr())
  if sub != "":
    return sub
  case input.kind:
  of nnkEmpty: return "v"
  of nnkPar: return mangle_type(self, input[0], still_const)
  of nnkRefTy:
    result &= "R" & mangle_type(self, input[0])
  of nnkPtrTy:
    result &= "P" & mangle_type(self, input[0])
  of nnkVarTy:
    result = mangle_type(self, input[0], false)
    if  result[0] notin '0'..'9':
      return result
  of nnkIdent, nnkStrLit:
    case $input:
    of "pointer":
      var ptrnode = newNimNode(nnkPtrTy)
      var varnode = newNimNode(nnkVarTy)
      varnode.add(newIdentNode("void"))
      ptrnode.add(varnode)
      return self.mangle_type(ptrnode, still_const)
    of  "string":
      let bs_type = parseExpr(
        """std > "__cxx11" > basic_string[var cchar,
          var (std>char_traits[var cchar]), var (std>allocator[var cchar])]""")
      result &= mangle_type(self, bs_type, false)
      # Debug string substitutions
      #for i in self.nested_nodes:
      #  hint ($i)
      #for i in 0..<self.known_nodes.len():
      #  hint("$1 - $2" % [number_to_substitution(i), self.known_nodes[i]])
    else:
      result &= mangle_typename(self, $input)
    if not still_const:
      return result
  of nnkBracketExpr:
    if input[0].kind == nnkIdent and $input[0] == "seq":
      var vector = input
      vector[0] = parseExpr("\"std\">vector")
      var varlocator = newNimNode(nnkVarTy)
      var allocator = newNimNode(nnkBracketExpr)
      allocator.add(parseExpr("\"std\">allocator"))
      allocator.add(vector[1])
      varlocator.add(allocator)
      vector.add(varlocator)
      return self.mangle_type(vector, still_const)
    let base = mangle_type(self, input[0], still_const)
    var arg: string = "I"
    for i in 1..<input.len():
      arg &= mangle_type(self, input[i])
    arg &= "E"
    if base[base.len()-1] == 'E':
      result &= base[0..base.len()-2] & arg & 'E'
    else:
      result &= base & arg
    return result
  of nnkInfix: # namespacing solution
    if input[0].kind != nnkIdent or $input[0] != ">":
      hint("Did you mean \">\" to specify namespace?")
      error("Unknown infix operation: $1!" % input.lispRepr)
    var submangle:MangleInfo = self
    let oldns: string = self.namespace
    case input[1].kind:
    of nnkIdent, nnkStrLit:
      let ns = $input[1]
      submangle = new[MangleInfo](ns, self)
    of nnkInfix:
      unwind_infixes(submangle, input[1])
    else:
      error("Unknown namespace specification: $1!" % input.lispRepr)
    result = mangle_type(submangle, input[2], still_const)
    self = new[MangleInfo](oldns, submangle)
  
  of nnkProcTy:
    expectKind(input[0], nnkFormalParams)
    let arguments = input[0]
    result = "F"
    for arg in arguments.children():
      if arg.kind == nnkIdentDefs:
        result &= self.mangle_type(arg[1])
      else:
        result &= self.mangle_type(arg)
    if arguments.len() < 2:
      result &= "v"
    result &= "E"
  else:
    hint(input.treeRepr())
    error("Unsupported NodeKind: " & $input.kind)
  self.remember(input.lispRepr)
  
