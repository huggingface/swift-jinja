//
//  Runtime.swift
//
//
//  Created by John Mai on 2024/3/22.
//

import Foundation

protocol RuntimeValue {
    associatedtype T
    var value: T { get set }

    var builtins: [String: any RuntimeValue] { get set }

    func bool() -> Bool
}

struct NumericValue: RuntimeValue {
    var value: any Numeric
    var builtins: [String: any RuntimeValue] = [:]

    func bool() -> Bool {
        self.value as? Int != 0
    }
}

struct BooleanValue: RuntimeValue {
    var value: Bool
    var builtins: [String: any RuntimeValue] = [:]

    func bool() -> Bool {
        self.value
    }
}

struct NullValue: RuntimeValue {
    var value: (any RuntimeValue)?
    var builtins: [String: any RuntimeValue] = [:]

    func bool() -> Bool {
        false
    }
}

struct UndefinedValue: RuntimeValue {
    var value: (any RuntimeValue)?
    var builtins: [String: any RuntimeValue] = [:]

    func bool() -> Bool {
        false
    }
}

struct ArrayValue: RuntimeValue {
    var value: [any RuntimeValue]
    var builtins: [String: any RuntimeValue] = [:]

    init(value: [any RuntimeValue]) {
        self.value = value
        self.builtins["length"] = FunctionValue(value: { _, _ in
            NumericValue(value: value.count)
        })
    }

    func bool() -> Bool {
        !self.value.isEmpty
    }
}

struct TupleValue: RuntimeValue {
    var value: ArrayValue
    var builtins: [String: any RuntimeValue] = [:]

    func bool() -> Bool {
        self.value.bool()
    }
}

struct ObjectValue: RuntimeValue {
    var value: [String: any RuntimeValue]
    var builtins: [String: any RuntimeValue] = [:]

    init(value: [String: any RuntimeValue]) {
        self.value = value
        self.builtins = [
            "get": FunctionValue(value: { args, _ in
                if let key = args[0] as? StringValue {
                    if let value = value.first(where: { $0.0 == key.value }) {
                        return value as! (any RuntimeValue)
                    }
                    else if args.count > 1 {
                        return args[1]
                    }
                    else {
                        return NullValue()
                    }
                }
                else {
                    throw JinjaError.runtime("Object key must be a string: got \(type(of:args[0]))")
                }
            }),
            "items": FunctionValue(value: { _, _ in
                var items: [ArrayValue] = []
                for (k, v) in value {
                    items.append(
                        ArrayValue(value: [
                            StringValue(value: k),
                            v,
                        ])
                    )
                }
                return items as! (any RuntimeValue)
            }),
        ]
    }

    func bool() -> Bool {
        !self.value.isEmpty
    }
}

struct FunctionValue: RuntimeValue {
    var value: ([any RuntimeValue], Environment) throws -> any RuntimeValue
    var builtins: [String: any RuntimeValue] = [:]

    func bool() -> Bool {
        true
    }
}

struct StringValue: RuntimeValue {
    var value: String
    var builtins: [String: any RuntimeValue] = [:]

    init(value: String) {
        self.value = value
        self.builtins = [
            "upper": FunctionValue(value: { _, _ in
                StringValue(value: value.uppercased())
            }),

            "lower": FunctionValue(value: { _, _ in
                StringValue(value: value.lowercased())
            }),

            "strip": FunctionValue(value: { _, _ in
                StringValue(value: value.trimmingCharacters(in: .whitespacesAndNewlines))
            }),

            "title": FunctionValue(value: { _, _ in
                StringValue(value: value.capitalized)
            }),

            "length": FunctionValue(value: { _, _ in
                NumericValue(value: value.count)
            }),
        ]
    }

    func bool() -> Bool {
        !self.value.isEmpty
    }
}

struct Interpreter {
    var global: Environment

    init(env: Environment?) {
        self.global = env ?? Environment()
    }

    func run(program: Program) throws -> any RuntimeValue {
        try self.evaluate(statement: program, environment: self.global)
    }

    func evaluateBlock(statements: [Statement], environment: Environment) throws -> StringValue {
        var result = ""
        for statement in statements {
            let lastEvaluated = try self.evaluate(statement: statement, environment: environment)

            if !(lastEvaluated is NullValue), !(lastEvaluated is UndefinedValue) {
                if let value = lastEvaluated.value as? String {
                    result += value
                }
                else {
                    switch lastEvaluated.value {
                    case let value as Int:
                        result += String(value)
                    case let value as String:
                        result += value
                    default:
                        throw JinjaError.runtime("Unknown value type:\(type(of: lastEvaluated.value))")
                    }
                }
            }
        }

        return StringValue(value: result)
    }

    func evalProgram(program: Program, environment: Environment) throws -> StringValue {
        try self.evaluateBlock(statements: program.body, environment: environment)
    }

    func evaluateSet(node: Set, environment: Environment) throws -> NullValue {
        let rhs = try self.evaluate(statement: node.value, environment: environment)
        if let identifier = node.assignee as? Identifier {
            let variableName = identifier.value
            try environment.setVariable(name: variableName, value: rhs)
        }
        else if let member = node.assignee as? MemberExpression {
            let object = try self.evaluate(statement: member.object, environment: environment)

            if var object = object as? ObjectValue {
                if let property = member.property as? Identifier {
                    object.value[property.value] = rhs
                }
                else {
                    throw JinjaError.runtime("Cannot assign to member with non-identifier property")
                }
            }
            else {
                throw JinjaError.runtime("Cannot assign to member of non-object")
            }
        }
        else {
            throw JinjaError.runtime("Invalid assignee type: \(type(of: node.assignee))")
        }

        return NullValue()
    }

    func evaluateIf(node: If, environment: Environment) throws -> StringValue {
        let test = try self.evaluate(statement: node.test, environment: environment)

        return try self.evaluateBlock(statements: test.bool() ? node.body : node.alternate, environment: environment)
    }

    func evaluateIdentifier(node: Identifier, environment: Environment) throws -> any RuntimeValue {
        environment.lookupVariable(name: node.value)
    }

    func evaluateFor(node: For, environment: Environment) throws -> any RuntimeValue {
        let scope = Environment(parent: environment)

        let iterable = try self.evaluate(statement: node.iterable, environment: scope)
        var result = ""
        if let iterable = iterable as? ArrayValue {
            for i in 0 ..< iterable.value.count {
                let loop: [String: any RuntimeValue] = [
                    "index": NumericValue(value: i + 1),
                    "index0": NumericValue(value: i),
                    "revindex": NumericValue(value: iterable.value.count - i),
                    "revindex0": NumericValue(value: iterable.value.count - i - 1),
                    "first": BooleanValue(value: i == 0),
                    "last": BooleanValue(value: i == iterable.value.count - 1),
                    "length": NumericValue(value: iterable.value.count),
                    "previtem": i > 0 ? iterable.value[i - 1] : UndefinedValue(),
                    "nextitem": i < iterable.value.count - 1 ? iterable.value[i + 1] : UndefinedValue(),
                ]

                try scope.setVariable(name: "loop", value: ObjectValue(value: loop))

                let current = iterable.value[i]

                if let identifier = node.loopvar as? Identifier {
                    try scope.setVariable(name: identifier.value, value: current)
                }
                else {
                }

                switch node.loopvar {
                case let identifier as Identifier:
                    try scope.setVariable(name: identifier.value, value: current)
                case let tupleLiteral as TupleLiteral:
                    if let current = current as? ArrayValue {
                        if tupleLiteral.value.count != current.value.count {
                            throw JinjaError.runtime(
                                "Too \(tupleLiteral.value.count > current.value.count ? "few" : "many") items to unpack"
                            )
                        }

                        for j in 0 ..< tupleLiteral.value.count {
                            if let identifier = tupleLiteral.value[j] as? Identifier {
                                try scope.setVariable(name: identifier.value, value: current.value[j])
                            }
                            else {
                                throw JinjaError.runtime(
                                    "Cannot unpack non-identifier type: \(type(of:tupleLiteral.value[j]))"
                                )
                            }
                        }
                    }
                    else {
                        throw JinjaError.runtime("Cannot unpack non-iterable type: \(type(of:current))")
                    }
                default:
                    throw JinjaError.syntaxNotSupported(String(describing: node.loopvar))
                }

                let evaluated = try self.evaluateBlock(statements: node.body, environment: scope)
                result += evaluated.value
            }
        }
        else {
            throw JinjaError.runtime("Expected iterable type in for loop: got \(type(of:iterable))")
        }

        return StringValue(value: result)
    }

    func evaluateBinaryExpression(node: BinaryExpression, environment: Environment) throws -> any RuntimeValue {
        let left = try self.evaluate(statement: node.left, environment: environment)

        if node.operation.value == "and" {
            return left.bool() ? try self.evaluate(statement: node.right, environment: environment) : left
        }
        else if node.operation.value == "or" {
            return left.bool() ? left : try self.evaluate(statement: node.right, environment: environment)
        }

        let right = try self.evaluate(statement: node.right, environment: environment)

        if node.operation.value == "==" {
            switch left.value {
            case let value as String:
                return BooleanValue(value: value == right.value as! String)
            case let value as Int:
                return BooleanValue(value: value == right.value as! Int)
            case let value as Bool:
                return BooleanValue(value: value == right.value as! Bool)
            default:
                throw JinjaError.runtime(
                    "Unknown left value type:\(type(of: left.value)), right value type:\(type(of: right.value))"
                )
            }
        }
        else if node.operation.value == "!=" {
            if type(of: left) != type(of: right) {
                return BooleanValue(value: true)
            }
            else {
                return BooleanValue(value: left.value as! AnyHashable != right.value as! AnyHashable)
            }
        }

        if left is UndefinedValue || right is UndefinedValue {
            throw JinjaError.runtime("Cannot perform operation on undefined values")
        }
        else if left is NullValue || right is NullValue {
            throw JinjaError.runtime("Cannot perform operation on null values")
        }
        else if let left = left as? NumericValue, let right = right as? NumericValue {
            switch node.operation.value {
            case "+": throw JinjaError.syntaxNotSupported("+")
            case "-": throw JinjaError.syntaxNotSupported("-")
            case "*": throw JinjaError.syntaxNotSupported("*")
            case "/": throw JinjaError.syntaxNotSupported("/")
            case "%":
                switch left.value {
                case is Int:
                    return NumericValue(value: left.value as! Int % (right.value as! Int))
                default:
                    throw JinjaError.runtime("Unknown value type:\(type(of: left.value))")
                }
            case "<": throw JinjaError.syntaxNotSupported("<")
            case ">": throw JinjaError.syntaxNotSupported(">")
            case ">=": throw JinjaError.syntaxNotSupported(">=")
            case "<=": throw JinjaError.syntaxNotSupported("<=")
            default:
                throw JinjaError.runtime("Unknown operation type:\(node.operation.value)")
            }
        }
        else if left is ArrayValue && right is ArrayValue {
            switch node.operation.value {
            case "+": break
            default:
                throw JinjaError.runtime("Unknown operation type:\(node.operation.value)")
            }
        }
        else if right is ArrayValue {
            throw JinjaError.syntaxNotSupported("right is ArrayValue")
        }

        if left is StringValue || right is StringValue {
            switch node.operation.value {
            case "+":
                var rightValue = ""
                var leftValue = ""
                switch right.value {
                case let value as String:
                    rightValue = value
                case let value as Int:
                    rightValue = String(value)
                case let value as Bool:
                    rightValue = String(value)
                default:
                    throw JinjaError.runtime("Unknown right value type:\(type(of: right.value))")
                }

                switch left.value {
                case let value as String:
                    leftValue = value
                case let value as Int:
                    leftValue = String(value)
                case let value as Bool:
                    rightValue = String(value)
                default:
                    throw JinjaError.runtime("Unknown left value type:\(type(of: left.value))")
                }

                return StringValue(value: leftValue + rightValue)
            default:
                break
            }
        }

        if let left = left as? StringValue, let right = right as? StringValue {
            switch node.operation.value {
            case "in":
                return BooleanValue(value: right.value.contains(left.value))
            case "not in":
                return BooleanValue(value: !right.value.contains(left.value))
            default:
                throw JinjaError.runtime("Unknown operation type:\(node.operation.value)")
            }
        }

        if left is StringValue, right is ObjectValue {
            switch node.operation.value {
            case "in":
                if let leftString = (left as? StringValue)?.value,
                    let rightObject = right as? ObjectValue
                {
                    return BooleanValue(value: rightObject.value.keys.contains(leftString))
                }
            case "not in":
                if let leftString = (left as? StringValue)?.value,
                    let rightObject = right as? ObjectValue
                {
                    return BooleanValue(value: !rightObject.value.keys.contains(leftString))
                }
            default:
                throw JinjaError.runtime(
                    "Unsupported operation '\(node.operation.value)' between StringValue and ObjectValue"
                )
            }
        }

        throw JinjaError.syntax(
            "Unknown operator '\(node.operation.value)' between \(type(of:left)) and \(type(of:right))"
        )
    }

    func evaluateSliceExpression(
        object: any RuntimeValue,
        expr: SliceExpression,
        environment: Environment
    ) throws -> any RuntimeValue {
        if !(object is ArrayValue || object is StringValue) {
            throw JinjaError.runtime("Slice object must be an array or string")
        }

        let start = try self.evaluate(statement: expr.start, environment: environment)
        let stop = try self.evaluate(statement: expr.stop, environment: environment)
        let step = try self.evaluate(statement: expr.step, environment: environment)

        if !(start is NumericValue || start is UndefinedValue) {
            throw JinjaError.runtime("Slice start must be numeric or undefined")
        }

        if !(stop is NumericValue || stop is UndefinedValue) {
            throw JinjaError.runtime("Slice stop must be numeric or undefined")
        }

        if !(step is NumericValue || step is UndefinedValue) {
            throw JinjaError.runtime("Slice step must be numeric or undefined")
        }

        if let object = object as? ArrayValue {
            return ArrayValue(
                value: slice(
                    object.value,
                    start: start.value as? Int,
                    stop: stop.value as? Int,
                    step: step.value as? Int
                )
            )
        }
        else if let object = object as? StringValue {
            return StringValue(
                value: slice(
                    Array(arrayLiteral: object.value),
                    start: start.value as? Int,
                    stop: stop.value as? Int,
                    step: step.value as? Int
                ).joined()
            )
        }

        throw JinjaError.runtime("Slice object must be an array or string")
    }

    func evaluateMemberExpression(expr: MemberExpression, environment: Environment) throws -> any RuntimeValue {
        let object = try self.evaluate(statement: expr.object, environment: environment)

        var property: any RuntimeValue
        if expr.computed {
            if let property = expr.property as? SliceExpression {
                return try self.evaluateSliceExpression(object: object, expr: property, environment: environment)
            }
            else {
                property = try self.evaluate(statement: expr.property, environment: environment)
            }
        }
        else {
            property = StringValue(value: (expr.property as! Identifier).value)
        }

        var value: (any RuntimeValue)?
        if let object = object as? ObjectValue {
            if let property = property as? StringValue {
                value = object.value[property.value] ?? object.builtins[property.value]
            }
            else {
                throw JinjaError.runtime("Cannot access property with non-string: got \(type(of:property))")
            }
        }
        else if object is ArrayValue || object is StringValue {
            if let property = property as? NumericValue {
                if let object = object as? ArrayValue {
                    let index = property.value as! Int
                    if index >= 0 {
                        value = object.value[index]
                    }
                    else {
                        value = object.value[object.value.count + index]
                    }
                }
                else if let object = object as? StringValue {
                    let index = object.value.index(object.value.startIndex, offsetBy: property.value as! Int)
                    value = StringValue(value: String(object.value[index]))
                }
            }
            else if let property = property as? StringValue {
                value = object.builtins[property.value]
            }
            else {
                throw JinjaError.runtime(
                    "Cannot access property with non-string/non-number: got \(type(of:property))"
                )
            }
        }
        else {
            if let property = property as? StringValue {
                value = object.builtins[property.value]!
            }
            else {
                throw JinjaError.runtime("Cannot access property with non-string: got \(type(of:property))")
            }
        }

        if let value {
            return value
        }
        else {
            return UndefinedValue()
        }
    }

    func evaluateUnaryExpression(node: UnaryExpression, environment: Environment) throws -> any RuntimeValue {
        let argument = try self.evaluate(statement: node.argument, environment: environment)

        switch node.operation.value {
        case "not":
            return BooleanValue(value: !argument.bool())
        default:
            throw JinjaError.syntax("Unknown operator: \(node.operation.value)")
        }
    }

    func evaluateCallExpression(expr: CallExpression, environment: Environment) throws -> any RuntimeValue {
        var args: [any RuntimeValue] = []
        var kwargs: [String: any RuntimeValue] = [:]

        for argument in expr.args {
            if let argument = argument as? KeywordArgumentExpression {
                kwargs[argument.key.value] = try self.evaluate(statement: argument.value, environment: environment)
            }
            else {
                try args.append(self.evaluate(statement: argument, environment: environment))
            }
        }

        if kwargs.count > 0 {
            args.append(ObjectValue(value: kwargs))
        }

        let fn = try self.evaluate(statement: expr.callee, environment: environment)

        if let fn = fn as? FunctionValue {
            return try fn.value(args, environment)
        }
        else {
            throw JinjaError.runtime("Cannot call something that is not a function: got \(type(of:fn))")
        }
    }

    func evaluateFilterExpression(node: FilterExpression, environment: Environment) throws -> any RuntimeValue {
        let operand = try evaluate(statement: node.operand, environment: environment)

        if let identifier = node.filter as? Identifier {
            if let arrayValue = operand as? ArrayValue {
                switch identifier.value {
                case "list":
                    return arrayValue
                case "first":
                    return arrayValue.value.first ?? UndefinedValue()
                case "last":
                    return arrayValue.value.last ?? UndefinedValue()
                case "length":
                    return NumericValue(value: arrayValue.value.count)
                case "reverse":
                    return ArrayValue(value: arrayValue.value.reversed())
                case "sort":
                    throw JinjaError.todo("TODO: ArrayValue filter sort")
                default:
                    throw JinjaError.runtime("Unknown ArrayValue filter: \(identifier.value)")
                }
            }
            else if let stringValue = operand as? StringValue {
                switch identifier.value {
                case "length":
                    return NumericValue(value: stringValue.value.count)
                case "upper":
                    return StringValue(value: stringValue.value.uppercased())
                case "lower":
                    return StringValue(value: stringValue.value.lowercased())
                case "title":
                    return StringValue(value: stringValue.value.capitalized)
                case "capitalize":
                    return StringValue(value: stringValue.value.capitalized)
                case "trim":
                    return StringValue(value: stringValue.value.trimmingCharacters(in: .whitespacesAndNewlines))
                default:
                    throw JinjaError.runtime("Unknown StringValue filter: \(identifier.value)")
                }
            }
            else if let numericValue = operand as? NumericValue {
                switch identifier.value {
                case "abs":
                    return NumericValue(value: abs(numericValue.value as! Int32))
                default:
                    throw JinjaError.runtime("Unknown NumericValue filter: \(identifier.value)")
                }
            }
            else if let objectValue = operand as? ObjectValue {
                switch identifier.value {
                case "items":
                    var items: [ArrayValue] = []
                    for (k, v) in objectValue.value {
                        items.append(
                            ArrayValue(value: [
                                StringValue(value: k),
                                v,
                            ])
                        )
                    }
                    return items as! (any RuntimeValue)
                case "length":
                    return NumericValue(value: objectValue.value.count)
                default:
                    throw JinjaError.runtime("Unknown ObjectValue filter: \(identifier.value)")
                }
            }

            throw JinjaError.runtime("Cannot apply filter \(operand.value) to type: \(type(of:operand))")
        }

        throw JinjaError.runtime("Unknown filter: \(node.filter)")
    }

    func evaluateTestExpression(node: TestExpression, environment: Environment) throws -> any RuntimeValue {
        let operand = try self.evaluate(statement: node.operand, environment: environment)

        if let testFunction = environment.tests[node.test.value] {
            let result = try testFunction(operand)
            return BooleanValue(value: node.negate ? !result : result)
        }
        else {
            throw JinjaError.runtime("Unknown test: \(node.test.value)")
        }
    }

    func evaluate(statement: Statement?, environment: Environment) throws -> any RuntimeValue {
        if let statement {
            switch statement {
            case let statement as Program:
                return try self.evalProgram(program: statement, environment: environment)
            case let statement as If:
                return try self.evaluateIf(node: statement, environment: environment)
            case let statement as StringLiteral:
                return StringValue(value: statement.value)
            case let statement as Set:
                return try self.evaluateSet(node: statement, environment: environment)
            case let statement as For:
                return try self.evaluateFor(node: statement, environment: environment)
            case let statement as Identifier:
                return try self.evaluateIdentifier(node: statement, environment: environment)
            case let statement as BinaryExpression:
                return try self.evaluateBinaryExpression(node: statement, environment: environment)
            case let statement as MemberExpression:
                return try self.evaluateMemberExpression(expr: statement, environment: environment)
            case let statement as UnaryExpression:
                return try self.evaluateUnaryExpression(node: statement, environment: environment)
            case let statement as NumericLiteral:
                return NumericValue(value: statement.value)
            case let statement as CallExpression:
                return try self.evaluateCallExpression(expr: statement, environment: environment)
            case let statement as BoolLiteral:
                return BooleanValue(value: statement.value)
            case let statement as FilterExpression:
                return try self.evaluateFilterExpression(node: statement, environment: environment)
            case let statement as TestExpression:
                return try self.evaluateTestExpression(node: statement, environment: environment)
            case is NullLiteral:
                return NullValue()
            default:
                throw JinjaError.runtime(
                    "Unknown node type: \(type(of:statement)), statement: \(String(describing: statement))"
                )
            }
        }
        else {
            return UndefinedValue()
        }
    }
}
