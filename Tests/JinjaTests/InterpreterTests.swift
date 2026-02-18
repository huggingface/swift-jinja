import Foundation
import Testing

@testable import Jinja

@Suite("Interpreter")
struct InterpreterTests {
    @Suite("Operators")
    struct OperatorTests {
        @Test("Floor division with integers")
        func floorDivisionIntegers() throws {
            let result = try Interpreter.evaluateBinaryValues(.floorDivide, .int(20), .int(7))
            #expect(result == .int(2))
        }

        @Test("Floor division with mixed types")
        func floorDivisionMixed() throws {
            let result = try Interpreter.evaluateBinaryValues(.floorDivide, .double(20.5), .int(7))
            #expect(result == .int(2))
        }

        @Test("Floor division by zero throws error")
        func floorDivisionByZero() throws {
            #expect(throws: JinjaError.self) {
                try Interpreter.evaluateBinaryValues(.floorDivide, .int(10), .int(0))
            }
        }

        @Test("Exponentiation with integers")
        func exponentiationIntegers() throws {
            let result = try Interpreter.evaluateBinaryValues(.power, .int(2), .int(3))
            #expect(result == .int(8))
        }

        @Test("Exponentiation with mixed types")
        func exponentiationMixed() throws {
            let result = try Interpreter.evaluateBinaryValues(.power, .int(2), .double(3.0))
            #expect(result == .double(8.0))
        }

        @Test("Exponentiation with negative exponent")
        func exponentiationNegative() throws {
            let result = try Interpreter.evaluateBinaryValues(.power, .int(2), .int(-2))
            #expect(result == .double(0.25))
        }

        @Test("Concatenation binary op")
        func concatenationBinaryOp() throws {
            let result = try Interpreter.evaluateBinaryValues(.concat, .string("a"), .string("b"))
            #expect(result == .string("ab"))
        }

        @Test("In binary op")
        func inBinaryOp() throws {
            let result = try Interpreter.evaluateBinaryValues(
                .in,
                .int(2),
                .array([.int(1), .int(2), .int(3)])
            )
            #expect(result == .boolean(true))
        }

        @Test("NotIn binary op")
        func notInBinaryOp() throws {
            let result = try Interpreter.evaluateBinaryValues(
                .notIn,
                .int(4),
                .array([.int(1), .int(2), .int(3)])
            )
            #expect(result == .boolean(true))
        }
    }

    // MARK: - Environment setInChain

    @Test("Environment setInChain falls through to current")
    func setInChainFallsThrough() throws {
        let env = Environment()
        env.setInChain(name: "newVar", value: .int(42))
        #expect(env["newVar"] == .int(42))
    }

    // MARK: - Ternary without alternate

    @Test("Ternary without alternate returns null")
    func ternaryWithoutAlternate() throws {
        let template = try Template("{{ x if false }}")
        let result = try template.render([:])
        #expect(result == "")
    }

    // MARK: - Computed member access

    @Test("Computed member access")
    func computedMemberAccess() throws {
        let template = try Template("{{ obj['key'] }}")
        let result = try template.render(["obj": .object(["key": .string("value")])])
        #expect(result == "value")
    }

    // MARK: - Call with macro

    @Test("Calling a macro value")
    func callMacro() throws {
        let template = try Template("{% macro greet(name) %}Hello {{ name }}{% endmacro %}{{ greet('World') }}")
        let result = try template.render([:])
        #expect(result == "Hello World")
    }

    // MARK: - Call with non-function

    @Test("Calling a non-callable throws")
    func callNonCallable() throws {
        let template = try Template("{{ x() }}")
        #expect(throws: JinjaError.self) {
            try template.render(["x": .int(42)])
        }
    }

    // MARK: - Call with splat unpacking

    @Test("Call with splat unpacking")
    func callWithSplatUnpacking() throws {
        let template = try Template("{{ range(*args) }}")
        let result = try template.render(["args": .array([.int(3)])])
        #expect(result == "[0, 1, 2]")
    }

    @Test("Splat on non-array throws")
    func splatOnNonArray() throws {
        let template = try Template("{{ range(*x) }}")
        #expect(throws: JinjaError.self) {
            try template.render(["x": .int(5)])
        }
    }

    // MARK: - For loop with object

    @Test("For loop over object")
    func forLoopOverObject() throws {
        let template = try Template("{% for k in obj %}{{ k }}{% endfor %}")
        let result = try template.render(["obj": .object(["a": .int(1), "b": .int(2)])])
        #expect(result == "ab")
    }

    @Test("For loop over object with tuple unpacking")
    func forLoopOverObjectTupleUnpacking() throws {
        let template = try Template("{% for k, v in obj.items() %}{{ k }}={{ v }} {% endfor %}")
        let result = try template.render(["obj": .object(["x": .int(1), "y": .int(2)])])
        #expect(result == "x=1 y=2 ")
    }

    @Test("For loop over string")
    func forLoopOverString() throws {
        let template = try Template("{% for c in s %}{{ c }}{% endfor %}")
        let result = try template.render(["s": .string("abc")])
        #expect(result == "abc")
    }

    // MARK: - For loop with tuple unpacking

    @Test("For loop with tuple unpacking in array")
    func forLoopTupleUnpackingArray() throws {
        let template = try Template("{% for a, b in items %}{{ a }}-{{ b }} {% endfor %}")
        let result = try template.render([
            "items": .array([
                .array([.string("x"), .int(1)]),
                .array([.string("y"), .int(2)]),
            ])
        ])
        #expect(result == "x-1 y-2 ")
    }

    // MARK: - For loop with empty iterable else block

    @Test("For loop with empty object else block")
    func forLoopEmptyObjectElse() throws {
        let template = try Template("{% for k in obj %}{{ k }}{% else %}empty{% endfor %}")
        let result = try template.render(["obj": .object([:])])
        #expect(result == "empty")
    }

    @Test("For loop with empty string else block")
    func forLoopEmptyStringElse() throws {
        let template = try Template("{% for c in s %}{{ c }}{% else %}empty{% endfor %}")
        let result = try template.render(["s": .string("")])
        #expect(result == "empty")
    }

    // MARK: - For loop with test

    @Test("Filtered for loop")
    func filteredForLoop() throws {
        let template = try Template("{% for x in items if x > 2 %}{{ x }}{% endfor %}")
        let result = try template.render(["items": .array([.int(1), .int(2), .int(3), .int(4)])])
        #expect(result == "34")
    }

    // MARK: - Set with body

    @Test("Set block with body")
    func setBlockWithBody() throws {
        let template = try Template("{% set content %}hello world{% endset %}{{ content }}")
        let result = try template.render([:])
        #expect(result == "hello world")
    }

    // MARK: - Filter blocks

    @Test("Filter block")
    func filterBlock() throws {
        let template = try Template("{% filter upper %}hello{% endfilter %}")
        let result = try template.render([:])
        #expect(result == "HELLO")
    }

    // MARK: - Generation blocks

    @Test("Generation block")
    func generationBlock() throws {
        let template = try Template("{% generation %}content{% endgeneration %}")
        let result = try template.render([:])
        #expect(result == "content")
    }

    // MARK: - Unary operations

    @Test("Unary plus on integer")
    func unaryPlusInteger() throws {
        let result = try Interpreter.evaluateUnaryValue(.plus, .int(5))
        #expect(result == .int(5))
    }

    @Test("Unary plus on double")
    func unaryPlusDouble() throws {
        let result = try Interpreter.evaluateUnaryValue(.plus, .double(3.14))
        #expect(result == .double(3.14))
    }

    @Test("Unary plus on non-numeric throws")
    func unaryPlusNonNumeric() throws {
        #expect(throws: JinjaError.self) {
            try Interpreter.evaluateUnaryValue(.plus, .string("hello"))
        }
    }

    @Test("Unary minus on double")
    func unaryMinusDouble() throws {
        let result = try Interpreter.evaluateUnaryValue(.minus, .double(3.14))
        #expect(result == .double(-3.14))
    }

    @Test("Splat operator throws")
    func splatOperatorThrows() throws {
        #expect(throws: JinjaError.self) {
            try Interpreter.evaluateUnaryValue(.splat, .array([.int(1)]))
        }
    }

    // MARK: - Computed member evaluation

    @Test("Array negative index")
    func arrayNegativeIndex() throws {
        let result = try Interpreter.evaluateComputedMember(
            .array([.int(1), .int(2), .int(3)]),
            .int(-1)
        )
        #expect(result == .int(3))
    }

    @Test("String index")
    func stringIndex() throws {
        let result = try Interpreter.evaluateComputedMember(.string("hello"), .int(1))
        #expect(result == .string("e"))
    }

    @Test("Array out of bounds")
    func arrayOutOfBounds() throws {
        let result = try Interpreter.evaluateComputedMember(.array([.int(1)]), .int(5))
        #expect(result == .undefined)
    }

    @Test("String out of bounds")
    func stringOutOfBounds() throws {
        let result = try Interpreter.evaluateComputedMember(.string("hi"), .int(5))
        #expect(result == .undefined)
    }

    @Test("Computed member default case")
    func computedMemberDefault() throws {
        let result = try Interpreter.evaluateComputedMember(.int(42), .int(0))
        #expect(result == .undefined)
    }

    // MARK: - Slice evaluation

    @Test("Array slice with step")
    func arraySliceWithStep() throws {
        let template = try Template("{{ items[::2] }}")
        let result = try template.render([
            "items": .array([.int(0), .int(1), .int(2), .int(3), .int(4)])
        ])
        #expect(result == "[0, 2, 4]")
    }

    @Test("Array slice with negative indices")
    func arraySliceWithNegativeIndices() throws {
        let template = try Template("{{ items[-3:-1] }}")
        let result = try template.render([
            "items": .array([.int(0), .int(1), .int(2), .int(3), .int(4)])
        ])
        #expect(result == "[2, 3]")
    }

    @Test("Slice step=0 throws")
    func sliceStepZero() throws {
        let template = try Template("{{ items[::0] }}")
        #expect(throws: JinjaError.self) {
            try template.render(["items": .array([.int(1)])])
        }
    }

    @Test("String slicing")
    func stringSlicing() throws {
        let template = try Template("{{ s[1:4] }}")
        let result = try template.render(["s": .string("hello")])
        #expect(result == "ell")
    }

    // MARK: - Evaluate test

    @Test("Unknown test throws")
    func unknownTestThrows() throws {
        #expect(throws: JinjaError.self) {
            try Interpreter.evaluateTest("nonexistent_test", [.int(1)], env: Environment())
        }
    }

    @Test("Env-provided test")
    func envProvidedTest() throws {
        let env = Environment()
        env["custom_test"] = .function { args, _, _ in
            .boolean(args.first == .int(42))
        }
        let result = try Interpreter.evaluateTest("custom_test", [.int(42)], env: env)
        #expect(result == true)
    }

    // MARK: - Evaluate filter

    @Test("Unknown filter throws")
    func unknownFilterThrows() throws {
        #expect(throws: JinjaError.self) {
            try Interpreter.evaluateFilter("nonexistent_filter", [.string("x")], kwargs: [:], env: Environment())
        }
    }

    @Test("Env-provided filter")
    func envProvidedFilter() throws {
        let env = Environment()
        env["custom_filter"] = .function { args, _, _ in
            if case let .string(s) = args.first {
                return .string(s + "!")
            }
            return .null
        }
        let result = try Interpreter.evaluateFilter("custom_filter", [.string("hi")], kwargs: [:], env: env)
        #expect(result == .string("hi!"))
    }

    // MARK: - Assignment

    @Test("Tuple assignment")
    func tupleAssignment() throws {
        let template = try Template("{% set a, b = [1, 2] %}{{ a }}-{{ b }}")
        let result = try template.render([:])
        #expect(result == "1-2")
    }

    @Test("Computed member assignment")
    func computedMemberAssignment() throws {
        let template = try Template("{% set ns = namespace(x=1) %}{% set ns['x'] = 2 %}{{ ns.x }}")
        let result = try template.render([:])
        #expect(result == "2")
    }

    @Test("Member assignment")
    func memberAssignment() throws {
        let template = try Template("{% set ns = namespace(x=1) %}{% set ns.x = 42 %}{{ ns.x }}")
        let result = try template.render([:])
        #expect(result == "42")
    }

    @Test("Invalid assignment target throws")
    func invalidAssignmentTarget() throws {
        #expect(throws: JinjaError.self) {
            try Interpreter.assign(target: .number(3.14), value: .int(1), env: Environment())
        }
    }

    // MARK: - executeStatementWithOutput

    @Test("If statement with truthy condition")
    func ifStatementTruthy() throws {
        let template = try Template("{% if true %}yes{% endif %}")
        let result = try template.render([:])
        #expect(result == "yes")
    }

    @Test("If statement with falsy condition and alternate")
    func ifStatementFalsyAlternate() throws {
        let template = try Template("{% if false %}yes{% else %}no{% endif %}")
        let result = try template.render([:])
        #expect(result == "no")
    }

    @Test("For loop with break")
    func forLoopBreak() throws {
        let template = try Template("{% for i in range(10) %}{% if i == 3 %}{% break %}{% endif %}{{ i }}{% endfor %}")
        let result = try template.render([:])
        #expect(result == "012")
    }

    @Test("For loop with continue")
    func forLoopContinue() throws {
        let template = try Template(
            "{% for i in range(5) %}{% if i == 2 %}{% continue %}{% endif %}{{ i }}{% endfor %}"
        )
        let result = try template.render([:])
        #expect(result == "0134")
    }

    @Test("For loop over non-iterable throws")
    func forLoopNonIterable() throws {
        let template = try Template("{% for x in items %}{{ x }}{% endfor %}")
        #expect(throws: JinjaError.self) {
            try template.render(["items": .int(42)])
        }
    }

    @Test("For loop with loop.cycle")
    func forLoopCycle() throws {
        let template = try Template("{% for i in range(4) %}{{ loop.cycle('a', 'b') }}{% endfor %}")
        let result = try template.render([:])
        #expect(result == "abab")
    }

    @Test("For loop variables")
    func forLoopVariables() throws {
        let template = try Template(
            "{% for i in [10, 20, 30] %}{{ loop.index }}-{{ loop.index0 }}-{{ loop.first }}-{{ loop.last }}-{{ loop.length }}-{{ loop.revindex }}-{{ loop.revindex0 }} {% endfor %}"
        )
        let result = try template.render([:])
        #expect(result == "1-0-true-false-3-3-2 2-1-false-false-3-2-1 3-2-false-true-3-1-0 ")
    }

    @Test("Call block with macro")
    func callBlockWithMacro() throws {
        let template = try Template(
            """
            {% macro render_dialog(title) %}<dialog>{{ title }}:{{ caller() }}</dialog>{% endmacro %}{% call render_dialog('Hello') %}World{% endcall %}
            """
        )
        let result = try template.render([:])
        #expect(result == "<dialog>Hello:World</dialog>")
    }

    @Test("Call block with non-callable throws")
    func callBlockNonCallable() throws {
        let template = try Template("{% call x() %}body{% endcall %}")
        #expect(throws: JinjaError.self) {
            try template.render(["x": .int(42)])
        }
    }

    @Test("Filter block with filter name")
    func filterBlockWithName() throws {
        let template = try Template("{% filter lower %}HELLO{% endfilter %}")
        let result = try template.render([:])
        #expect(result == "hello")
    }

    @Test("Set statement with expression value")
    func setStatementExpression() throws {
        let template = try Template("{% set x = 1 + 2 %}{{ x }}")
        let result = try template.render([:])
        #expect(result == "3")
    }

    @Test("Macro with default parameters")
    func macroWithDefaults() throws {
        let template = try Template("{% macro greet(name='World') %}Hello {{ name }}{% endmacro %}{{ greet() }}")
        let result = try template.render([:])
        #expect(result == "Hello World")
    }

    @Test("Macro with keyword arguments")
    func macroWithKwargs() throws {
        let template = try Template(
            "{% macro greet(name, greeting='Hi') %}{{ greeting }} {{ name }}{% endmacro %}{{ greet('Bob', greeting='Hey') }}"
        )
        let result = try template.render([:])
        #expect(result == "Hey Bob")
    }

    @Test("Generation block renders content")
    func generationBlockContent() throws {
        let template = try Template("before{% generation %}inside{% endgeneration %}after")
        let result = try template.render([:])
        #expect(result == "beforeinsideafter")
    }

    @Test("Nested for loops")
    func nestedForLoops() throws {
        let template = try Template(
            "{% for i in [1, 2] %}{% for j in ['a', 'b'] %}{{ i }}{{ j }}{% endfor %}{% endfor %}"
        )
        let result = try template.render([:])
        #expect(result == "1a1b2a2b")
    }

    @Test("For loop tuple unpacking with object items()")
    func forLoopTupleUnpackingObjectItems() throws {
        let template = try Template("{% for k, v in obj.items() %}{{ k }}:{{ v }};{% endfor %}")
        let result = try template.render(["obj": .object(["x": .int(1)])])
        #expect(result == "x:1;")
    }

    @Test("Tuple assignment mismatch throws")
    func tupleAssignmentMismatch() throws {
        let template = try Template("{% set a, b, c = [1, 2] %}{{ a }}")
        #expect(throws: JinjaError.self) {
            try template.render([:])
        }
    }

    @Test("Tuple assignment non-array throws")
    func tupleAssignmentNonArray() throws {
        let template = try Template("{% set a, b = 42 %}{{ a }}")
        #expect(throws: JinjaError.self) {
            try template.render([:])
        }
    }

    // MARK: - Division

    @Test("Division with integers")
    func divisionIntegers() throws {
        let result = try Interpreter.evaluateBinaryValues(.divide, .int(10), .int(3))
        #expect(result == .double(10.0 / 3.0))
    }

    @Test("Division by zero throws error")
    func divisionByZero() throws {
        #expect(throws: JinjaError.self) {
            try Interpreter.evaluateBinaryValues(.divide, .int(10), .int(0))
        }
    }

    @Test("Division with doubles")
    func divisionDoubles() throws {
        let result = try Interpreter.evaluateBinaryValues(.divide, .double(7.5), .double(2.5))
        #expect(result == .double(3.0))
    }

    @Test("Division with mixed types")
    func divisionMixed() throws {
        let result = try Interpreter.evaluateBinaryValues(.divide, .int(10), .double(2.5))
        #expect(result == .double(4.0))
    }

    // MARK: - And / Or

    @Test("And with truthy left returns right")
    func andTruthyLeft() throws {
        let result = try Interpreter.evaluateBinaryValues(.and, .int(1), .string("hello"))
        #expect(result == .string("hello"))
    }

    @Test("And with falsy left returns left")
    func andFalsyLeft() throws {
        let result = try Interpreter.evaluateBinaryValues(.and, .int(0), .string("hello"))
        #expect(result == .int(0))
    }

    @Test("Or with truthy left returns left")
    func orTruthyLeft() throws {
        let result = try Interpreter.evaluateBinaryValues(.or, .int(1), .string("hello"))
        #expect(result == .int(1))
    }

    @Test("Or with falsy left returns right")
    func orFalsyLeft() throws {
        let result = try Interpreter.evaluateBinaryValues(.or, .int(0), .string("hello"))
        #expect(result == .string("hello"))
    }

    @Test("Or with both falsy returns right")
    func orBothFalsy() throws {
        let result = try Interpreter.evaluateBinaryValues(.or, .boolean(false), .int(0))
        #expect(result == .int(0))
    }

    // MARK: - resolveCallArguments

    @Test("resolveCallArguments positional and keyword conflict throws")
    func resolveCallArgumentsConflict() throws {
        #expect(throws: JinjaError.self) {
            try resolveCallArguments(
                args: [.string("value")],
                kwargs: ["name": .string("other")],
                parameters: ["name"],
                defaults: [:]
            )
        }
    }

    @Test("resolveCallArguments unexpected keyword throws")
    func resolveCallArgumentsUnexpectedKeyword() throws {
        #expect(throws: JinjaError.self) {
            try resolveCallArguments(
                args: [],
                kwargs: ["unknown": .string("value")],
                parameters: ["name"],
                defaults: ["name": .string("default")]
            )
        }
    }

    @Test("resolveCallArguments missing required argument throws")
    func resolveCallArgumentsMissingRequired() throws {
        #expect(throws: JinjaError.self) {
            try resolveCallArguments(
                args: [],
                kwargs: [:],
                parameters: ["required_param"],
                defaults: [:]
            )
        }
    }

    @Test("resolveCallArguments applies defaults")
    func resolveCallArgumentsDefaults() throws {
        let result = try resolveCallArguments(
            args: [],
            kwargs: [:],
            parameters: ["name"],
            defaults: ["name": .string("default")]
        )
        #expect(result["name"] == .string("default"))
    }

    @Test("resolveCallArguments positional overrides default")
    func resolveCallArgumentsPositionalOverridesDefault() throws {
        let result = try resolveCallArguments(
            args: [.string("provided")],
            kwargs: [:],
            parameters: ["name"],
            defaults: ["name": .string("default")]
        )
        #expect(result["name"] == .string("provided"))
    }

    @Test("resolveCallArguments extra positional args ignored")
    func resolveCallArgumentsExtraPositional() throws {
        let result = try resolveCallArguments(
            args: [.string("a"), .string("b"), .string("extra")],
            kwargs: [:],
            parameters: ["first", "second"],
            defaults: [:]
        )
        #expect(result["first"] == .string("a"))
        #expect(result["second"] == .string("b"))
        #expect(result.count == 2)
    }
}
