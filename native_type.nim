from state import State, source_declaration
from cppclass import CppClass, newCppClass, declaration
from strutils import `%`
from sequtils import repeat, concat
import macros

proc generate_type_declaration(state: State): string =
  ## Generates string for "importcpp" pragma
  let namespace_prefix = 
    if state.namespace != nil : state.namespace & "::"
    else: ""
  let template_params =
    if state.class.template_args.len > 0: "<'0>"
    else: ""
  namespace_prefix & state.class.cppname & template_params

proc generate_type_pragma(state: State): NimNode =
  ## Generates pragma for type declaration
  let importcpp = newTree(nnkExprColonExpr,
    newIdentNode("importcpp"),
    newStrLitNode(state.generate_type_declaration))
  newTree(nnkPragma, importcpp, state.source_declaration)

proc generate_type*(state: State): NimNode =
  ## Generates type declaration for current class
  ## Returned declaration must be placed into TypeSection node
  ## Given state must include class field with current CppClass
  assert(state.class != nil, "Can not generate type without state.class!")
  let emptyobject = newTree(nnkObjectTy, repeat(newEmptyNode(), 3))
  let pragmaexpr = newTree(nnkPragmaExpr,
    newIdentNode(state.class.name).postfix("*"),
    state.generate_type_pragma)
  let generics =
    if state.class.template_args.len > 0:
      newTree(nnkGenericParams,
        newTree(nnkIdentDefs,
          state.class.template_args.concat(repeat(newEmptyNode(), 2))
          )
        )
    else: newEmptyNode()
  newTree(nnkTypeDef, pragmaexpr, generics, emptyobject)

when isMainModule:
  from test_tools import test
  from macros import parseExpr
  proc n(x: string): NimNode = x.parseExpr
  static:
    let sc = newCppClass(n"SomeClass")
    let scs = State(class: sc)
    let tc = newCppClass(n""""_tclass" as TemplateClass[T, V]""")
    let tcs = State(class: tc)
    test(scs.generate_type(),
      n"""type SomeClass* {.importcpp:"SomeClass", nodecl.} = object"""[0])
    test(tcs.generate_type(),
      n"""type
        TemplateClass* {.importcpp:"_tclass<'0>", nodecl.} [T, V] = object"""[0])
