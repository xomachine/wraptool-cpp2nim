from state import State, source_declaration
from cppclass import CppClass, newCppClass, declaration
from native_proc import generate_proc, generate_proc_call
from native_var import generate_var
from strutils import `%`
from sequtils import repeat, concat, toSeq, filter, map
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

proc generate_type*(state: State, statements: NimNode = newStmtList()): NimNode =
  ## Generates type declaration for current class
  ## Returned declaration must be placed into TypeSection node
  ## Given state must include class field with current CppClass
  assert(state.class != nil, "Can not generate type without state.class!")
  statements.expectKind(nnkStmtList)
  let class_fields = toSeq(statements.children())
    .filter(proc (i: NimNode): bool = 
      (i.kind == nnkCall or (i.kind == nnkInfix and $i[0] == "as")))
    .map(proc (i:NimNode): NimNode = generate_var(state, i))
  let reclist = if class_fields.len > 0 : newTree(nnkRecList, class_fields)
    else: newEmptyNode()
  let emptyobject = newTree(nnkObjectTy, repeat(newEmptyNode(), 2).concat(@[reclist]))
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

proc generate_basic_constructor*(state: State): NimNode =
  ## Generates basic constructor for a class with name "new<ClassName>"
  assert(state.class != nil, "Can not generate constructor without state.class!")
  let constructor_declaration = parseExpr("""proc $1()""" % state.class.name)
  generate_proc(state, constructor_declaration)
  
proc generate_destructor*(state: State): NimNode =
  ## Generates destructor for a class with declaration destroy(this: ClassName)
  assert(state.class != nil, "Can not generate constructor without state.class!")
  generate_proc(state, parseExpr("""proc `=destroy`()"""))
  
when isMainModule:
  from test_tools import test
  from macros import parseExpr
  proc n(x: string): NimNode {.compileTime.} = x.parseExpr
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
    test(scs.generate_basic_constructor(),
      n"""proc newSomeClass*(): SomeClass
      {.importcpp:"SomeClass(@)", nodecl, constructor.}""")
    test(scs.generate_destructor(),
      n"""proc `=destroy`*(this: var SomeClass)
      {.importcpp:"#.SomeClass::~SomeClass(@)", nodecl, destructor.}""")
    
