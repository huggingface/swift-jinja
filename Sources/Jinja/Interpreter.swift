import Foundation
@_exported import OrderedCollections

// MARK: - Context

/// A context is a dictionary of variables and their values.
public typealias Context = [String: Value]

// MARK: - Environment

/// Execution environment that stores variables and provides context for template rendering.
///
/// The environment maintains the variable scope during template execution and provides
/// configuration options that affect rendering behavior.
public final class Environment: @unchecked Sendable {
    private let parent: Environment?
    private(set) var variables: [String: Value] = [:]

    /// The number of macro and `caller` invocations in progress
    /// when this environment was created.
    /// A child environment starts with the depth of its parent.
    var callDepth: Int

    /// Settings that adjust the behavior of built-in filters.
    public struct Policies: Sendable {
        /// The serializer corresponding to Jinja2's `json.dumps_function` policy.
        public var jsonSerializer: JSON.Serializer

        /// Options corresponding to Jinja2's `json.dumps_kwargs` policy.
        /// Explicit non-null `tojson` arguments override these options for that call.
        public var jsonDumpsOptions: JSON.DumpsOptions

        /// Creates policies with Transformers-compatible defaults.
        public init(
            jsonSerializer: JSON.Serializer = .standard,
            jsonDumpsOptions: JSON.DumpsOptions = .init(ensureASCII: false)
        ) {
            self.jsonSerializer = jsonSerializer
            self.jsonDumpsOptions = jsonDumpsOptions
        }

        /// Plain JSON with non-ASCII characters and insertion order preserved.
        public static let transformers = Policies()

        /// HTML-safe JSON with sorted keys and non-ASCII characters escaped.
        public static let jinja2 = Policies(
            jsonSerializer: .htmlSafe,
            jsonDumpsOptions: .init(ensureASCII: true, sortKeys: true)
        )
    }

    /// Settings that adjust how built-in filters behave.
    ///
    /// Policies are inherited from the parent environment until any policy is set.
    /// Mutating a policy copies all inherited settings into this environment;
    /// subsequent parent changes do not affect that copy.
    /// Root environments default to ``Policies/transformers``.
    /// Set `environment.policies = .jinja2` for sorted, ASCII, HTML-safe JSON.
    public var policies: Policies {
        get { policyStorage ?? parent?.policies ?? Environment.defaultPolicies }
        set { policyStorage = newValue }
    }
    private var policyStorage: Policies?

    /// The policies a root environment starts with.
    public static let defaultPolicies: Policies = .transformers

    // MARK: -

    /// Creates a new environment with optional parent and initial variables.
    ///
    /// An environment without a parent starts with the built-in globals,
    /// such as `range` and `namespace`.
    ///
    /// - Parameters:
    ///   - parent: The parent environment to inherit variables from
    ///   - initial: The initial variables to set in this environment
    public init(
        parent: Environment? = nil,
        initial: [String: Value] = [:]
    ) {
        self.parent = parent
        self.variables = initial
        self.callDepth = parent?.callDepth ?? 0

        if parent == nil {
            // Only add built-ins to the root environment to avoid duplication
            for (name, value) in Globals.builtIn {
                self.variables[name] = value
            }
        }
    }

    /// Gets or sets a variable in the environment.
    ///
    /// When getting a variable, this looks in the current environment first,
    /// then in parent environments. Returns `.undefined` if the variable is not found.
    ///
    /// - Parameter name: The variable name
    /// - Returns: The value associated with the variable name, or `.undefined`
    public subscript(name: String) -> Value {
        get {
            if let value = variables[name] {
                return value
            }

            // Check parent environment
            if let parent = parent {
                return parent[name]
            }

            return .undefined
        }
        set {
            variables[name] = newValue
        }
    }

    /// Sets a variable in the environment where it was originally defined.
    /// This searches up the environment chain to find where the variable exists
    /// and updates it there, ensuring namespace mutations persist across scopes.
    func setInChain(name: String, value: Value) {
        // Check if the variable exists in the current environment's variables
        if variables[name] != nil {
            self[name] = value
            return
        }

        // Search up the parent chain to find where the variable is defined
        if let parentEnv = parent {
            parentEnv.setInChain(name: name, value: value)
            return
        }

        // Fallback to setting in the current environment
        self[name] = value
    }
}

// MARK: - Interpreter

/// Internal control flow exceptions for loop statements.
enum ControlFlow: Error, Sendable {
    /// Control flow exception for break statement.
    case `break`
    /// Control flow exception for continue statement.
    case `continue`
}

/// Executes parsed Jinja template nodes to produce rendered output.
public enum Interpreter {
    /// Interprets nodes and renders them to a string using the given environment.
    ///
    /// - Parameters:
    ///   - nodes: The AST nodes to interpret and render
    ///   - environment: The execution environment containing variables
    /// - Returns: The rendered template output as a string
    /// - Throws: `RuntimeError` if an error occurs during interpretation
    public static func interpret(_ nodes: [Node], environment: Environment) throws -> String {
        // Use the fast path with synchronous environment
        let env = Environment(initial: environment.variables)
        env.policies = environment.policies
        var buffer = ""
        buffer.reserveCapacity(1024)
        try interpret(nodes, env: env, into: &buffer)
        return buffer
    }

    // MARK: -

    static func interpret(
        _ nodes: [Node],
        env: Environment,
        into buffer: inout String
    )
        throws
    {
        for node in nodes {
            try interpretNode(node, env: env, into: &buffer)
        }
    }

    static func interpretNode(
        _ node: Node,
        env: Environment,
        into buffer: inout String
    )
        throws
    {
        switch node {
        case let .text(content):
            buffer.append(content)

        case .comment:
            // Comments are ignored during execution
            break

        case let .expression(expr):
            let value = try evaluateExpression(expr, env: env)
            buffer.append(value.description)

        case let .statement(stmt):
            try executeStatementWithOutput(stmt, env: env, into: &buffer)
        }
    }

    static func evaluateExpression(_ expr: Expression, env: Environment) throws -> Value {
        switch expr {
        case let .string(value):
            return .string(value)

        case let .number(value):
            return .double(value)

        case let .integer(value):
            return .int(value)

        case let .boolean(value):
            return .boolean(value)

        case .null:
            return .null

        case let .array(elements):
            let values = try elements.map { try evaluateExpression($0, env: env) }
            return .array(values)

        case let .tuple(elements):
            let values = try elements.map { try evaluateExpression($0, env: env) }
            return .array(values)  // Tuples are represented as arrays in the runtime

        case let .object(pairs):
            let dict = try pairs.mapValues { try evaluateExpression($0, env: env) }
            return .object(dict)

        case let .identifier(name):
            return env[name]

        case let .unary(op, operand):
            let value = try evaluateExpression(operand, env: env)
            return try evaluateUnaryValue(op, value)

        case let .binary(op, left, right):
            let leftValue = try evaluateExpression(left, env: env)

            // Handle short-circuiting operators
            switch op {
            case .and:
                return leftValue.isTruthy ? try evaluateExpression(right, env: env) : leftValue
            case .or:
                return leftValue.isTruthy ? leftValue : try evaluateExpression(right, env: env)
            default:
                let rightValue = try evaluateExpression(right, env: env)
                return try evaluateBinaryValues(op, leftValue, rightValue)
            }

        case let .ternary(value, test, alternate):
            let testValue = try evaluateExpression(test, env: env)
            if testValue.isTruthy {
                return try evaluateExpression(value, env: env)
            } else if let alternate = alternate {
                return try evaluateExpression(alternate, env: env)
            } else {
                return .undefined
            }

        case let .member(object, property, computed):
            let objectValue = try evaluateExpression(object, env: env)

            if computed {
                let propertyValue = try evaluateExpression(property, env: env)
                return try evaluateComputedMember(objectValue, propertyValue)
            } else {
                guard case let .identifier(propertyName) = property else {
                    throw JinjaError.runtime("Property access requires identifier")
                }
                return try PropertyMembers.evaluate(objectValue, propertyName)
            }

        case let .filter(operand, filterName, args, kwargs):
            let operandValue = try evaluateExpression(operand, env: env)
            let argValues = try [operandValue] + args.map { try evaluateExpression($0, env: env) }
            let kwargValues = try kwargs.mapValues { try evaluateExpression($0, env: env) }
            return try evaluateFilter(filterName, argValues, kwargs: kwargValues, env: env)

        case let .test(operand, testName, args, negated):
            let operandValue = try evaluateExpression(operand, env: env)
            let argValues = try [operandValue] + args.map { try evaluateExpression($0, env: env) }
            let result = try evaluateTest(testName, argValues, env: env)
            return .boolean(negated ? !result : result)

        case let .call(callableExpr, argsExpr, kwargsExpr):
            let callableValue = try evaluateExpression(callableExpr, env: env)

            // Handle unpacking in arguments
            var argValues: [Value] = []
            for argExpr in argsExpr {
                if case let .unary(.splat, expr) = argExpr {
                    // Unpack the array/tuple
                    let value = try evaluateExpression(expr, env: env)
                    if case let .array(items) = value {
                        argValues.append(contentsOf: items)
                    } else {
                        throw JinjaError.runtime("Cannot unpack non-array value")
                    }
                } else {
                    argValues.append(try evaluateExpression(argExpr, env: env))
                }
            }

            let kwargs = try kwargsExpr.mapValues { try evaluateExpression($0, env: env) }

            switch callableValue {
            case .function(let function):
                return try function(argValues, kwargs, env)
            case .macro(let macro):
                return try callMacro(
                    macro: macro,
                    arguments: argValues,
                    keywordArguments: kwargs,
                    env: env
                )
            default:
                throw JinjaError.runtime("Cannot call non-function value")
            }

        case let .slice(array, start, stop, step):
            let value = try evaluateExpression(array, env: env)
            return try evaluateSlice(value: value, start: start, stop: stop, step: step, env: env)
        }
    }

    /// Synchronous statement execution with output
    static func executeStatementWithOutput(
        _ statement: Statement,
        env: Environment,
        into buffer: inout String
    )
        throws
    {
        switch statement {
        case let .`if`(test, body, alternate):
            let testValue = try evaluateExpression(test, env: env)
            let nodesToExecute = testValue.isTruthy ? body : alternate

            for node in nodesToExecute {
                try interpretNode(node, env: env, into: &buffer)
            }

        case let .for(loopVar, iterable, body, elseBody, test):
            let iterableValue = try evaluateExpression(iterable, env: env)

            // The values that the loop iterates over,
            // which are also the `loop.previtem`/`loop.nextitem` items,
            // per Python jinja2 `LoopContext`.
            var items: [Value]
            switch iterableValue {
            case let .array(values):
                items = values
            case let .object(dict):
                // Keys for a single loop variable,
                // and `[key, value]` pairs for tuple unpacking (`for k, v in d`),
                // where Jinja2 would unpack each key instead.
                switch loopVar {
                case .single:
                    items = dict.keys.map { Value($0) }
                case .tuple:
                    items = dict.map { .array([Value($0.key), $0.value]) }
                }
            case let .string(str):
                items = str.map { .string(String($0)) }
            case .undefined:
                // Jinja2's `Undefined` iterates as an empty sequence.
                items = []
            default:
                throw JinjaError.runtime("Cannot iterate over non-iterable value")
            }

            // Jinja2 computes the loop variables, and whether the `else` block runs,
            // over the items that pass the test.
            // The test sees the loop variables, but not this loop's `loop`.
            // Like Jinja2, the loop tests each item just before the body runs with it,
            // so the test sees changes that the body makes to a namespace.
            // When the body reads `loop.last`, `loop.length`, `loop.revindex`,
            // `loop.revindex0`, or `loop.nextitem`, the loop tests every item first.
            // Then a test that reads state that the body changes can differ from Jinja2,
            // which tests later items only when the body reads one of those attributes.
            let testEnv = Environment(parent: env)
            var testEachItem = false
            if let test = test {
                if bodyReadsLaterItems(body) {
                    items = try items.filter { item in
                        try bindLoopVariables(loopVar, to: item, in: testEnv)
                        return try evaluateExpression(test, env: testEnv).isTruthy
                    }
                } else {
                    testEachItem = true
                }
            }

            let childEnv = Environment(parent: env)
            var index = 0
            var previtem = Value.undefined
            for item in items {
                if testEachItem, let test = test {
                    try bindLoopVariables(loopVar, to: item, in: testEnv)
                    if !(try evaluateExpression(test, env: testEnv).isTruthy) { continue }
                }

                try bindLoopVariables(loopVar, to: item, in: childEnv)
                childEnv["loop"] = makeLoopObject(
                    index: index,
                    previtem: previtem,
                    items: testEachItem ? nil : items
                )
                index += 1
                previtem = item

                var shouldBreak = false
                for node in body {
                    do {
                        try interpretNode(node, env: childEnv, into: &buffer)
                    } catch ControlFlow.break {
                        shouldBreak = true
                        break
                    } catch ControlFlow.continue {
                        break  // Break from inner loop (current iteration)
                    }
                }
                if shouldBreak { break }
            }

            if index == 0 {
                for node in elseBody {
                    try interpretNode(node, env: env, into: &buffer)
                }
            }

        case let .set(target, value, body):
            if let valueExpr = value {
                let evaluatedValue = try evaluateExpression(valueExpr, env: env)
                try assign(target: target, value: evaluatedValue, env: env)
            } else {
                var bodyBuffer = ""
                try interpret(body, env: env, into: &bodyBuffer)
                let renderedBody = bodyBuffer
                let valueToAssign = Value.string(renderedBody)
                try assign(target: target, value: valueToAssign, env: env)
            }

        case let .macro(name, parameters, defaults, body):
            try registerMacro(
                name: name,
                parameters: parameters,
                defaults: defaults,
                body: body,
                env: env
            )

        case let .program(nodes):
            try interpret(nodes, env: env, into: &buffer)

        case let .call(callExpr, callerParameters, body):
            let callable: Expression
            let args: [Expression]
            let kwargs: [String: Expression]
            switch callExpr {
            case let .call(c, a, k):
                callable = c
                args = a
                kwargs = k
            default:
                callable = callExpr
                args = []
                kwargs = [:]
            }

            let callableValue = try evaluateExpression(callable, env: env)

            let callTimeEnv = Environment(parent: env)
            callTimeEnv["caller"] = .function { callerArgs, _, callerEnv in
                let bodyEnv = Environment(parent: env)
                bodyEnv.callDepth = try nextCallDepth(after: callerEnv)
                for (paramName, value) in zip(callerParameters ?? [], callerArgs) {
                    guard case let .identifier(paramName) = paramName else {
                        throw JinjaError.runtime("Caller parameter must be an identifier")
                    }
                    bodyEnv[paramName] = value
                }
                var bodyBuffer = ""
                try interpret(body, env: bodyEnv, into: &bodyBuffer)
                return .string(bodyBuffer)
            }

            let finalArgs = try args.map { try evaluateExpression($0, env: env) }
            let finalKwargs = try kwargs.mapValues { try evaluateExpression($0, env: env) }

            switch callableValue {
            case .function(let function):
                let result = try function(finalArgs, finalKwargs, callTimeEnv)
                buffer.append(result.description)
            case .macro(let macro):
                let result = try callMacro(
                    macro: macro,
                    arguments: finalArgs,
                    keywordArguments: finalKwargs,
                    env: callTimeEnv
                )
                buffer.append(result.description)
            default:
                throw JinjaError.runtime("Cannot call non-function value")
            }

        case let .filter(filterExpr, body):
            var bodyBuffer = ""
            try interpret(body, env: env, into: &bodyBuffer)
            let renderedBody = bodyBuffer

            if case let .filter(_, name, args, _) = filterExpr {
                var filterArgs = [Value.string(renderedBody)]
                filterArgs.append(contentsOf: try args.map { try evaluateExpression($0, env: env) })
                // TODO: Handle kwargs in filters if necessary
                let filteredValue = try evaluateFilter(name, filterArgs, kwargs: [:], env: env)
                buffer.append(filteredValue.description)
            } else if case let .identifier(name) = filterExpr {
                let filteredValue = try evaluateFilter(
                    name,
                    [.string(renderedBody)],
                    kwargs: [:],
                    env: env
                )
                buffer.append(filteredValue.description)
            } else {
                throw JinjaError.runtime("Invalid filter expression in filter statement")
            }

        case let .generation(body):
            try interpret(body, env: env, into: &buffer)

        case .break:
            throw ControlFlow.break
        case .continue:
            throw ControlFlow.continue
        }
    }

    static func executeStatement(_ statement: Statement, env: Environment) throws {
        switch statement {
        case let .set(target, value, body):
            if let valueExpr = value {
                let evaluatedValue = try evaluateExpression(valueExpr, env: env)
                try assign(target: target, value: evaluatedValue, env: env)
            } else {
                var bodyBuffer = ""
                try interpret(body, env: env, into: &bodyBuffer)
                let renderedBody = bodyBuffer
                let valueToAssign = Value.string(renderedBody)
                try assign(target: target, value: valueToAssign, env: env)
            }

        case let .macro(name, parameters, defaults, body):
            try registerMacro(
                name: name,
                parameters: parameters,
                defaults: defaults,
                body: body,
                env: env
            )

        // These statements do not produce output directly or are handled elsewhere.
        case .if, .for, .program, .break, .continue, .call, .filter, .generation:
            break
        }
    }

    static func assign(target: Expression, value: Value, env: Environment) throws {
        switch target {
        case .identifier(let name):
            env[name] = value
        case .tuple(let expressions):
            guard case let .array(values) = value else {
                throw JinjaError.runtime("Cannot unpack non-array value for tuple assignment.")
            }
            guard expressions.count == values.count else {
                throw JinjaError.runtime(
                    "Tuple assignment mismatch: \(expressions.count) variables and \(values.count) values."
                )
            }
            for (expr, val) in zip(expressions, values) {
                try assign(target: expr, value: val, env: env)
            }
        case .member(let objectExpr, let propertyExpr, let computed):
            // Handle property assignment like ns.foo = 'bar'
            let objectValue = try evaluateExpression(objectExpr, env: env)

            if computed {
                let propertyValue = try evaluateExpression(propertyExpr, env: env)
                guard let key = ObjectKey(propertyValue) else {
                    throw JinjaError.runtime("Computed property key must be a string or integer")
                }
                if case var .object(dict) = objectValue {
                    dict[key] = value
                    // Update the object in the environment
                    if case let .identifier(name) = objectExpr {
                        env.setInChain(name: name, value: .object(dict))
                    }
                }
            } else {
                guard case let .identifier(propertyName) = propertyExpr else {
                    throw JinjaError.runtime("Property assignment requires identifier")
                }
                if case var .object(dict) = objectValue {
                    dict[.string(propertyName)] = value
                    // Update the object in the environment
                    if case let .identifier(name) = objectExpr {
                        env.setInChain(name: name, value: .object(dict))
                    }
                }
            }
        default:
            throw JinjaError.runtime("Invalid target for assignment: \(target)")
        }
    }

    // MARK: -

    static func registerMacro(
        name: String,
        parameters: [String],
        defaults: OrderedDictionary<String, Expression>,
        body: [Node],
        env: Environment
    ) throws {
        env[name] = .macro(
            Macro(name: name, parameters: parameters, defaults: defaults, body: body)
        )
    }

    /// The maximum number of nested macro and `caller` invocations.
    ///
    /// Swift can't recover from a stack overflow, so a template that recurses without end
    /// would crash the process, where Jinja2 raises `RecursionError`.
    /// The stack that each nested call takes grows with how deeply the macro body nests blocks.
    /// Measured on a thread with a 512 KB stack in a release build on arm64,
    /// a call takes about 3 KB for `{{ r() }}`,
    /// 6 KB for `{% if n %}{{ r(n - 1) }}{% endif %}`,
    /// and 19 KB for the type macro of the Hermes 3 tool-use template,
    /// which recurses from an `elif` branch inside a `for` loop.
    /// At 20 calls, that macro used 377 KB of the 512 KB,
    /// so 16 calls take about 300 KB,
    /// which leaves room for the frames of the code that renders the template.
    /// 32 calls of that macro would overflow a 512 KB stack.
    /// Debug builds take about 2.7 times as much stack per call.
    /// Jinja2 has no limit of its own;
    /// it allows about 250 nested macro calls under Python's default recursion limit.
    static let maximumCallDepth = 16

    /// Returns the call depth for an invocation from the given environment.
    ///
    /// - Throws: `JinjaError.runtime` if the invocation would exceed ``maximumCallDepth``.
    static func nextCallDepth(after env: Environment) throws -> Int {
        guard env.callDepth < maximumCallDepth else {
            throw JinjaError.runtime("Maximum recursion depth of \(maximumCallDepth) exceeded")
        }
        return env.callDepth + 1
    }

    static func callMacro(
        macro: Macro,
        arguments: [Value],
        keywordArguments: [String: Value],
        env: Environment
    ) throws -> Value {
        let macroEnv = Environment(parent: env)
        macroEnv.callDepth = try nextCallDepth(after: env)

        let caller = env["caller"]
        if caller != .undefined {
            macroEnv["caller"] = caller
        }

        // Start with defaults
        for (key, expr) in macro.defaults {
            // Evaluate defaults in current env
            let val = try evaluateExpression(expr, env: env)
            macroEnv[key] = val
        }

        // Bind positional args
        for (index, paramName) in macro.parameters.enumerated() {
            let value =
                index < arguments.count ? arguments[index] : macroEnv[paramName]
            macroEnv[paramName] = value
        }

        // Bind keyword args
        for (key, value) in keywordArguments {
            macroEnv[key] = value
        }

        var macroBuffer = ""
        try interpret(macro.body, env: macroEnv, into: &macroBuffer)
        return .string(macroBuffer)
    }

    static func evaluateBinaryValues(
        _ op: Expression.BinaryOp,
        _ left: Value,
        _ right: Value
    ) throws
        -> Value
    {
        switch op {
        case .add:
            return try left.add(with: right)
        case .subtract:
            return try left.subtract(by: right)
        case .multiply:
            return try left.multiply(by: right)
        case .divide:
            return try left.divide(by: right)
        case .floorDivide:
            return try left.floorDivide(by: right)
        case .power:
            return try left.power(by: right)
        case .modulo:
            return try left.modulo(by: right)
        case .concat:
            return try left.concatenate(with: right)
        case .equal:
            return .boolean(left.isEquivalent(to: right))
        case .notEqual:
            return .boolean(!left.isEquivalent(to: right))
        case .less:
            return .boolean(try left.compare(to: right) < 0)
        case .lessEqual:
            return .boolean(try left.compare(to: right) <= 0)
        case .greater:
            return .boolean(try left.compare(to: right) > 0)
        case .greaterEqual:
            return .boolean(try left.compare(to: right) >= 0)
        case .and:
            return left.isTruthy ? right : left
        case .or:
            return left.isTruthy ? left : right
        case .`in`:
            return .boolean(try left.isContained(in: right))
        case .notIn:
            return .boolean(!(try left.isContained(in: right)))
        }
    }

    static func evaluateUnaryValue(_ op: Expression.UnaryOp, _ value: Value) throws -> Value {
        switch op {
        case .not:
            return .boolean(!value.isTruthy)
        case .minus:
            switch value {
            case let .double(n):
                return .double(-n)
            case let .int(i):
                return .int(try checkedInt(Int(0).subtractingReportingOverflow(i), "-(\(i))"))
            default:
                throw JinjaError.runtime("Cannot negate non-numeric value")
            }
        case .plus:
            switch value {
            case .double, .int:
                return value
            default:
                throw JinjaError.runtime("Cannot apply unary plus to non-numeric value")
            }
        case .splat:
            // This should not be evaluated directly - it's only used for unpacking in calls
            throw JinjaError.runtime("Unpacking operator can only be used in function calls")
        }
    }

    static func evaluateComputedMember(_ object: Value, _ property: Value) throws -> Value {
        switch (object, property) {
        case let (.array(arr), .int(index)):
            let safeIndex = index < 0 ? arr.count + index : index
            guard safeIndex >= 0 && safeIndex < arr.count else {
                return .undefined
            }
            return arr[safeIndex]

        case let (.object(obj), .string(key)):
            return obj[.string(key)] ?? .undefined

        case let (.object(obj), .int(key)):
            return obj[.int(key)] ?? .undefined

        case let (.string(str), .int(index)):
            let safeIndex = index < 0 ? str.count + index : index
            guard safeIndex >= 0 && safeIndex < str.count else {
                return .undefined
            }
            let char = str[str.index(str.startIndex, offsetBy: safeIndex)]
            return .string(String(char))

        default:
            return .undefined
        }
    }

    static func evaluateTest(_ testName: String, _ argValues: [Value], env: Environment)
        throws -> Bool
    {
        // Try environment-provided tests first
        let testValue = env[testName]
        if case let .function(fn) = testValue {
            let result = try fn(argValues, [:], env)
            if case let .boolean(b) = result { return b }
            return result.isTruthy
        }

        // Fallback to built-in tests
        if let testFunction = Tests.builtIn[testName] {
            return try testFunction(argValues, [:], env)
        }

        throw JinjaError.runtime("Unknown test: \(testName)")
    }

    static func evaluateFilter(
        _ filterName: String,
        _ argValues: [Value],
        kwargs: [String: Value],
        env: Environment
    )
        throws -> Value
    {
        // Try environment-provided filters first
        let filterValue = env[filterName]
        if case let .function(fn) = filterValue {
            return try fn(argValues, kwargs, env)
        }

        // Fallback to built-in filters
        if let filterFunction = Filters.builtIn[filterName] {
            return try filterFunction(argValues, kwargs, env)
        }

        throw JinjaError.runtime("Unknown filter: \(filterName)")
    }

    /// Assigns an item of a for loop to the loop variables.
    private static func bindLoopVariables(
        _ loopVar: Statement.LoopVar,
        to item: Value,
        in env: Environment
    ) throws {
        switch loopVar {
        case let .single(varName):
            env[varName] = item
        case let .tuple(varNames):
            // Arrays unpack by position, as in Python.
            guard case let .array(values) = item else {
                throw JinjaError.runtime(
                    "Cannot unpack \(typeName(of: item)) into \(varNames.count) loop variables"
                )
            }
            guard values.count == varNames.count else {
                throw JinjaError.runtime(
                    "Cannot unpack array of \(values.count) values into \(varNames.count) loop variables"
                )
            }
            for (varName, value) in zip(varNames, values) {
                env[varName] = value
            }
        }
    }

    /// Returns the `loop` object for an iteration of a for loop.
    ///
    /// - Parameters:
    ///   - index: The zero-based index of the iteration.
    ///   - previtem: The item of the previous iteration, or `.undefined`.
    ///   - items: All the items of the loop,
    ///     or `nil` when the loop tests each item as it reaches it.
    ///     Without them, `loop` has no `last`, `length`, `revindex`,
    ///     `revindex0`, or `nextitem`.
    private static func makeLoopObject(
        index: Int,
        previtem: Value,
        items: [Value]?
    ) -> Value {
        var loopContext: OrderedDictionary<ObjectKey, Value> = [
            "index": .int(index + 1),
            "index0": .int(index),
            "first": .boolean(index == 0),
        ]
        if let items = items {
            let count = items.count
            loopContext["last"] = .boolean(index == count - 1)
            loopContext["length"] = .int(count)
            loopContext["revindex"] = .int(count - index)
            loopContext["revindex0"] = .int(count - index - 1)
        }
        loopContext["previtem"] = previtem
        if let items = items {
            loopContext["nextitem"] = index + 1 < items.count ? items[index + 1] : .undefined
        }

        loopContext["cycle"] = .function { args, _, _ in
            guard !args.isEmpty else { return .string("") }
            let cycleIndex = index % args.count
            return args[cycleIndex]
        }

        return .object(loopContext)
    }

    /// The `loop` attributes that Jinja2's `LoopContext` computes
    /// without the later items of the loop.
    private static let loopAttributesWithoutLaterItems: Set<String> = [
        "index", "index0", "first", "previtem", "cycle",
    ]

    /// Returns whether a for loop body may read a `loop` attribute
    /// that needs the later items of the loop, such as `loop.last` or `loop.length`.
    ///
    /// The check is conservative: any use of `loop` other than an attribute
    /// in ``loopAttributesWithoutLaterItems`` counts,
    /// such as `loop['index']` or passing `loop` to a macro.
    /// The body of a nested for loop doesn't count,
    /// because its `loop` is the nested loop's.
    private static func bodyReadsLaterItems(_ nodes: [Node]) -> Bool {
        nodes.contains { node in
            switch node {
            case .text, .comment:
                return false
            case let .expression(expr):
                return readsLaterItems(expr)
            case let .statement(statement):
                switch statement {
                case let .program(nodes), let .generation(nodes):
                    return bodyReadsLaterItems(nodes)
                case let .set(target, value, body):
                    return readsLaterItems(target) || value.map(readsLaterItems) == true
                        || bodyReadsLaterItems(body)
                case let .if(test, body, alternate):
                    return readsLaterItems(test) || bodyReadsLaterItems(body)
                        || bodyReadsLaterItems(alternate)
                case let .for(_, iterable, _, elseBody, test):
                    return readsLaterItems(iterable) || test.map(readsLaterItems) == true
                        || bodyReadsLaterItems(elseBody)
                case let .macro(_, _, defaults, body):
                    return defaults.values.contains(where: readsLaterItems)
                        || bodyReadsLaterItems(body)
                case .break, .continue:
                    return false
                case let .call(callable, callerArgs, body):
                    return readsLaterItems(callable)
                        || (callerArgs ?? []).contains(where: readsLaterItems)
                        || bodyReadsLaterItems(body)
                case let .filter(filterExpr, body):
                    return readsLaterItems(filterExpr) || bodyReadsLaterItems(body)
                }
            }
        }
    }

    /// Returns whether an expression may read a `loop` attribute
    /// that needs the later items of the loop.
    private static func readsLaterItems(_ expr: Expression) -> Bool {
        switch expr {
        case let .member(.identifier("loop"), .identifier(name), computed: false):
            return !loopAttributesWithoutLaterItems.contains(name)
        case .identifier(let name):
            return name == "loop"
        case .string, .number, .integer, .boolean, .null:
            return false
        case let .array(values), let .tuple(values):
            return values.contains(where: readsLaterItems)
        case let .object(pairs):
            return pairs.values.contains(where: readsLaterItems)
        case let .unary(_, operand):
            return readsLaterItems(operand)
        case let .binary(_, left, right):
            return readsLaterItems(left) || readsLaterItems(right)
        case let .ternary(value, test, alternate):
            return readsLaterItems(value) || readsLaterItems(test)
                || alternate.map(readsLaterItems) == true
        case let .call(callee, args, kwargs):
            return readsLaterItems(callee) || args.contains(where: readsLaterItems)
                || kwargs.values.contains(where: readsLaterItems)
        case let .member(object, property, computed):
            // The property of `foo.loop` is a name, not a variable.
            return readsLaterItems(object) || (computed && readsLaterItems(property))
        case let .slice(object, start, stop, step):
            return readsLaterItems(object) || [start, stop, step].contains { $0.map(readsLaterItems) == true }
        case let .filter(operand, _, args, kwargs):
            return readsLaterItems(operand) || args.contains(where: readsLaterItems)
                || kwargs.values.contains(where: readsLaterItems)
        case let .test(operand, _, args, _):
            return readsLaterItems(operand) || args.contains(where: readsLaterItems)
        }
    }

    /// The name of a value's type, for error messages.
    private static func typeName(of value: Value) -> String {
        switch value {
        case .null: return "none"
        case .undefined: return "undefined"
        case .boolean: return "boolean"
        case .int: return "int"
        case .double: return "float"
        case .string: return "string"
        case .array: return "array"
        case .object: return "object"
        case .function: return "function"
        case .macro: return "macro"
        }
    }

    private static func evaluateSlice(
        value: Value,
        start: Expression?,
        stop: Expression?,
        step: Expression?,
        env: Environment
    ) throws -> Value {
        let startVal = try start.map { try evaluateExpression($0, env: env) }
        let stopVal = try stop.map { try evaluateExpression($0, env: env) }
        let stepVal = try step.map { try evaluateExpression($0, env: env) }

        let step: Int
        if let s = stepVal, case let .int(val) = s {
            if val == 0 { throw JinjaError.runtime("Slice step cannot be zero") }
            step = val
        } else {
            step = 1
        }

        switch value {
        case .array(let items):
            let count = items.count

            let startIdx: Int
            if let s = startVal, case let .int(val) = s {
                startIdx = val >= 0 ? val : count + val
            } else {
                startIdx = step > 0 ? 0 : count - 1
            }

            let stopIdx: Int
            if let s = stopVal, case let .int(val) = s {
                stopIdx = val >= 0 ? val : count + val
            } else {
                stopIdx = step > 0 ? count : -1
            }

            var result: [Value] = []
            for i in stride(from: startIdx, to: stopIdx, by: step) {
                if i >= 0 && i < count {
                    result.append(items[i])
                }
            }
            return .array(result)

        case .string(let str):
            let count = str.count

            let startIdx: Int
            if let s = startVal, case let .int(val) = s {
                startIdx = val >= 0 ? val : count + val
            } else {
                startIdx = step > 0 ? 0 : count - 1
            }

            let stopIdx: Int
            if let s = stopVal, case let .int(val) = s {
                stopIdx = val >= 0 ? val : count + val
            } else {
                stopIdx = step > 0 ? count : -1
            }

            var result = ""
            for i in stride(from: startIdx, to: stopIdx, by: step) {
                if i >= 0 && i < count {
                    let index = str.index(str.startIndex, offsetBy: i)
                    result.append(str[index])
                }
            }
            return .string(String(result))

        default:
            throw JinjaError.runtime("Slice requires array or string")
        }
    }
}
