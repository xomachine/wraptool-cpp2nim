import macros
from strutils import `%`, startsWith
from sequtils import toSeq
from native_proc import generate_proc
from native_type import generate_type, generate_basic_constructor, generate_destructor
from native_var import generate_var
from state import State, newState, append, source_declaration, SourceType
from cppclass import newCppClass


proc wrap(state: State, expressions: NimNode): NimNode =
  let inside_class = state.class != nil
  let dynlib = not state.source_declaration.repr.startsWith("header")
  var types = newNimNode(nnkStmtList)
  var others = newNimNode(nnkStmtList)
  for expression in expressions.children:
    case expression.kind
    of nnkCommand:
      assert(expression.len > 0, "Incorrect command statement at $1" %
        expression.lineinfo())
      expression[0].expectKind(nnkIdent)
      case $expression[0]
      of "namespace":
        assert(expression.len == 3, "Incorrect namespace declaration at $1" %
          expression.lineinfo())
        expression[1].expectKind(nnkStrLit)
        expression[2].expectKind(nnkStmtList)
        let namespace = $expression[1]
        let body = expression[2]
        let namespace_content = state.append(namespace).wrap(body)
        others.add(toSeq(namespace_content.children()))
      of "class":
        assert(expression.len == 3, "Incorrect class declaration at $1" %
          expression.lineinfo())
        expression[2].expectKind(nnkStmtList)
        let body = expression[2]
        let cppclass = newCppClass(expression[1])
        let class_state = state.append(class = cppclass)
        types.add(class_state.generate_type(body))
        others.add(class_state.generate_basic_constructor())
        # Should be added when destructors become stable
        #others.add(parseExpr("{.experimental.}"))
        #others.add(class_state.generate_destructor())
        let class_content = class_state.wrap(body)
        others.add(toSeq(class_content.children()))
      else:
        error("Unknown command: $1 $2" % [$expression, expression.lineinfo()])
    of nnkProcDef:
      others.add(state.generate_proc(expression))
    of nnkCall, nnkInfix:
      if dynlib:
        error("Constants and global variables cannot be imported" &
          " without header: $1 $2" %
          [$expression, expression.lineinfo()])
      if inside_class: continue # Class fields already handled by generate_type
      let value_declaration = state.generate_var(expression)
      others.add(newTree(nnkVarSection, value_declaration))
    else:
      error("Expression not supported in wrapper.$1 \n $2" %
            [expression.treeRepr(), expression.lineinfo()])
    
    result = newNimNode(nnkStmtList)
    if types.len > 0:
      result.add(newTree(nnkTypeSection, toSeq(types.children())))
    result.add(toSeq(others.children()))


macro wrapheader*(header: expr, imports: expr): expr =
  ## Wraps all supplied annotations as C++ stuff included from file
  ##
  ##
  ## Usage:
  ##
  ## .. code-block:: nim
  ##   wrapheader "<string>":
  ##     namespace "std":
  ##       proc stoi(str: cstring, idx: ptr culong, base: cint) # import "stoi" function
  ##       class "string" as CppString: # import std::string as CppString type
  ##         proc c_str(): cstring      # import method of class
  ##         proc CppString(s:cstring)  # overloaded constructor
  ##         # (default constructor and destructor generated automaticaly)
  ##     ...
  ##   var cppstr = newCppString("str") # constructors have names
  ##                                    # compilled from "new" word and class name in Nim
  ##   echo(cppstr.c_str())  # method can be called by familiar way
  ##   lc.destroyCppString() # destructors have names compiled from "destroy" word and class name in Nim
  ##   # Destructors usage is unnesessary according to Nim manual
  ##   # http://nim-lang.org/docs/manual.html#importcpp-pragma-wrapping-destructors
  ##     ...
  ##   wrapheader "<foo.h>":
  ##     FOO_CONSTANT: cint             # constants can be wrapped
  ##     "__BarConst" as BAR_CONST:cint # and renamed if nessesary
  ##     class Bar[T]: # namespace can be ommited as well as C++ name
  ##                   # if in C++ class has the same name with Nims one
  ##                   # actually class can be a template
  ##       proc Bar(x: T, y: cint)      # You may use template identifier in constructors
  ##                                    # from declaration of class
  ##       proc some_method(): T        # as well as in methods
  ##       foofield: cint               # class field annotations allowed
  ##       "__bar_field" as barfield: T # field can be renamed and its type can be generic parameter
  ##      ...
  ##    let fooconst = FOO_CONST                   # constants can be used in code as usually
  ##    var bar = newBar[string]("str", BAR_CONST) # costructors are formed as generics
  ##    assert(type(bar.some_method()) is string)  # either methods
  ##
  ## class annotation without parameters generates new type, default constructor and destructor for this type
  
  let state = newState(header, SourceType.header)
  state.wrap(imports)

macro wrapdynlib*(lib: expr, imports: expr): expr =
  ## Wraps all supplied annotations as C++ stuff dynamicly loaded from file
  ##
  ##
  ## Usage:
  ##
  ## .. code-block:: nim
  ##   wrapdynlib "libfoo.so": # libraries also can be "wrapped"
  ##     # FOO_CONST: cint     # Constants cannot be wrapped from libraries
  ##     class Bar[T]: # Other things are the same with wrapheader
  ##       proc Bar(x: T, y: int)
  ##       proc some_method(): T
  ##      ...
  ##    var bar = newBar[string]("str", 5)
  ##    assert(type(bar.some_method()) is string)
  ##
  ## class annotation without parameters generates new type, default constructor and destructor for this type
  let state = newState(lib, SourceType.dynlib)
  state.wrap(imports)
