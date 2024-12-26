//
//  Parser.swift
//
//
//  Created by John Mai on 2024/3/21.
//

import Foundation

func parse(tokens: [Token]) throws -> Program {
    var program = Program()
    var current = 0

    @discardableResult
    func expect(type: TokenType, error: String) throws -> Token {
        let prev = tokens[current]
        current += 1
        if prev.type != type {
            throw JinjaError.parser("Parser Error: \(error). \(prev.type) != \(type).")
        }

        return prev
    }

    func parseArgumentsList() throws -> [Statement] {
        var args: [Expression] = []

        while !typeof(.closeParen) {
            var argument = try parseExpression()

            if typeof(.equals) {
                current += 1

                if let identifier = argument as? Identifier {
                    let value = try parseExpression()
                    argument = KeywordArgumentExpression(key: identifier, value: value as! Expression)
                }
                else {
                    throw JinjaError.syntax("Expected identifier for keyword argument")
                }
            }

            args.append(argument as! Expression)

            if typeof(.comma) {
                current += 1
            }
        }

        return args
    }

    func parseArgs() throws -> [Statement] {
        try expect(type: .openParen, error: "Expected opening parenthesis for arguments list")

        let args = try parseArgumentsList()

        try expect(type: .closeParen, error: "Expected closing parenthesis for arguments list")

        return args
    }

    func parseText() throws -> StringLiteral {
        try StringLiteral(value: expect(type: .text, error: "Expected text token").value)
    }

    func parseCallExpression(callee: Statement) throws -> CallExpression {
        var args: [Expression] = []

        for arg in try parseArgs() {
            args.append(arg as! Expression)
        }

        var callExpression = CallExpression(callee: callee as! Expression, args: args)

        if typeof(.openParen) {
            callExpression = try parseCallExpression(callee: callExpression)
        }

        return callExpression
    }

    func parseMemberExpressionArgumentsList() throws -> Statement {
        var slices: [Statement?] = []
        var isSlice = false

        while !typeof(.closeSquareBracket) {
            if typeof(.colon) {
                slices.append(nil)
                current += 1
                isSlice = true
            }
            else {
                try slices.append(parseExpression())
                if typeof(.colon) {
                    current += 1
                    isSlice = true
                }
            }
        }

        if slices.isEmpty {
            throw JinjaError.syntax("Expected at least one argument for member/slice expression")
        }

        if isSlice {
            if slices.count > 3 {
                throw JinjaError.syntax("Expected 0-3 arguments for slice expression")
            }

            return SliceExpression(
                start: slices[0] as? Expression,
                stop: slices.count > 1 ? slices[1] as? Expression : nil,
                step: slices.count > 2 ? slices[2] as? Expression : nil
            )
        }

        return slices[0]!
    }

    func parseMemberExpression() throws -> Statement {
        var object = try parsePrimaryExpression()

        while typeof(.dot) || typeof(.openSquareBracket) {
            let operation = tokens[current]
            current += 1
            var property: Statement

            let computed = operation.type != .dot

            if computed {
                property = try parseMemberExpressionArgumentsList()
                try expect(type: .closeSquareBracket, error: "Expected closing square bracket")
            }
            else {
                property = try parsePrimaryExpression()
                if !(property is Identifier) {
                    throw JinjaError.syntax("Expected identifier following dot operator")
                }
            }

            object = MemberExpression(
                object: object as! Expression,
                property: property as! Expression,
                computed: computed
            )
        }

        return object
    }

    func parseCallMemberExpression() throws -> Statement {
        let member = try parseMemberExpression()

        if typeof(.openParen) {
            return try parseCallExpression(callee: member)
        }

        return member
    }

    func parseFilterExpression() throws -> Statement {
        var operand = try parseCallMemberExpression()

        while typeof(.pipe) {
            current += 1
            var filter = try parsePrimaryExpression()
            if !(filter is Identifier) {
                throw JinjaError.syntax("Expected identifier for the test")
            }

            if typeof(.openParen) {
                filter = try parseCallExpression(callee: filter)
            }

            if let filter = filter as? Filter {
                operand = FilterExpression(operand: operand as! Expression, filter: filter)
            }
        }

        return operand
    }

    func parseTestExpression() throws -> Statement {
        var operand = try parseFilterExpression()

        while typeof(.is) {
            current += 1
            let negate = typeof(.not)
            if negate {
                current += 1
            }
            var filter = try parsePrimaryExpression()
            if let boolLiteralFilter = filter as? BoolLiteral {
                filter = Identifier(value: String(boolLiteralFilter.value))
            }
            else if filter is NullLiteral {
                filter = Identifier(value: "none")
            }
            if let test = filter as? Identifier {
                operand = TestExpression(operand: operand as! Expression, negate: negate, test: test)
            }
            else {
                throw JinjaError.syntax("Expected identifier for the test")
            }
        }
        return operand
    }

    func parseMultiplicativeExpression() throws -> Statement {
        var left = try parseTestExpression()

        while typeof(.multiplicativeBinaryOperator) {
            let operation = tokens[current]
            current += 1
            let right = try parseTestExpression()
            left = BinaryExpression(operation: operation, left: left as! Expression, right: right as! Expression)
        }
        return left
    }

    func parseAdditiveExpression() throws -> Statement {
        var left = try parseMultiplicativeExpression()
        while typeof(.additiveBinaryOperator) {
            let operation = tokens[current]
            current += 1
            let right = try parseMultiplicativeExpression()
            left = BinaryExpression(operation: operation, left: left as! Expression, right: right as! Expression)
        }
        return left
    }

    func parseComparisonExpression() throws -> Statement {
        var left = try parseAdditiveExpression()
        while typeof(.comparisonBinaryOperator) || typeof(.in) || typeof(.notIn) {
            let operation = tokens[current]
            current += 1
            let right = try parseAdditiveExpression()
            left = BinaryExpression(operation: operation, left: left as! Expression, right: right as! Expression)
        }

        return left
    }

    func parseLogicalNegationExpression() throws -> Statement {
        var right: UnaryExpression?

        while typeof(.not) {
            let operation = tokens[current]
            current += 1
            let argument = try parseLogicalNegationExpression()
            right = UnaryExpression(operation: operation, argument: argument as! Expression)
        }

        if let right {
            return right
        }
        else {
            return try parseComparisonExpression()
        }
    }

    func parseLogicalAndExpression() throws -> Statement {
        var left = try parseLogicalNegationExpression()
        while typeof(.and) {
            let operation = tokens[current]
            current += 1
            let right = try parseLogicalNegationExpression()
            left = BinaryExpression(operation: operation, left: left as! Expression, right: right as! Expression)
        }

        return left
    }

    func parseLogicalOrExpression() throws -> Statement {
        var left = try parseLogicalAndExpression()

        while typeof(.or) {
            let operation = tokens[current]
            current += 1
            let right = try parseLogicalAndExpression()
            left = BinaryExpression(operation: operation, left: left as! Expression, right: right as! Expression)
        }
        return left
    }

    func parseTernaryExpression() throws -> Statement {
        let a = try parseLogicalOrExpression()
        if typeof(.if) {
            current += 1
            let test = try parseLogicalOrExpression()
            try expect(type: .else, error: "Expected else token")
            let b = try parseLogicalOrExpression()
            return If(test: test as! Expression, body: [a], alternate: [b])
        }

        return a
    }

    func parseExpression() throws -> Statement {
        try parseTernaryExpression()
    }

    func typeof(_ types: TokenType...) -> Bool {
        guard current + types.count <= tokens.count else {
            return false
        }

        for (index, type) in types.enumerated() {
            if type != tokens[current + index].type {
                return false
            }
        }

        return true
    }

    func parseSetStatement() throws -> Statement {
        let left = try parseExpression()

        if typeof(.equals) {
            current += 1
            let value = try parseSetStatement()

            return Set(assignee: left as! Expression, value: value as! Expression)
        }

        return left
    }

    func parseIfStatement() throws -> Statement {
        let test = try parseExpression()

        try expect(type: .closeStatement, error: "Expected closing statement token")

        var body: [Statement] = []
        var alternate: [Statement] = []

        while !(tokens[current].type == .openStatement
            && (tokens[current + 1].type == .elseIf || tokens[current + 1].type == .else
                || tokens[current + 1].type == .endIf))
        {
            try body.append(parseAny())
        }
        if tokens[current].type == .openStatement, tokens[current + 1].type != .endIf {
            current += 1
            if typeof(.elseIf) {
                try expect(type: .elseIf, error: "Expected elseif token")
                try alternate.append(parseIfStatement())
            }
            else {
                try expect(type: .else, error: "Expected else token")
                try expect(type: .closeStatement, error: "Expected closing statement token")

                while !(tokens[current].type == .openStatement && tokens[current + 1].type == .endIf) {
                    try alternate.append(parseAny())
                }
            }
        }
        return If(test: test as! Expression, body: body, alternate: alternate)
    }

    func parsePrimaryExpression() throws -> Statement {
        let token = tokens[current]
        switch token.type {
        case .numericLiteral:
            current += 1
            return NumericLiteral(value: Int(token.value) ?? 0)
        case .stringLiteral:
            current += 1
            return StringLiteral(value: token.value)
        case .booleanLiteral:
            current += 1
            return BoolLiteral(value: token.value == "true")
        case .nullLiteral:
            current += 1
            return NullLiteral()
        case .identifier:
            current += 1
            return Identifier(value: token.value)
        case .openParen:
            current += 1
            let expression = try parseExpressionSequence()
            if tokens[current].type != .closeParen {
                throw JinjaError.syntax("Expected closing parenthesis, got \(tokens[current].type) instead")
            }
            current += 1
            return expression
        case .openSquareBracket:
            current += 1
            var values: [Expression] = []
            while !typeof(.closeSquareBracket) {
                try values.append(parseExpression() as! Expression)
                if typeof(.comma) {
                    current += 1
                }
            }
            current += 1
            return ArrayLiteral(value: values)
        case .openCurlyBracket:
            current += 1
            var values: [(Expression, Expression)] = []
            while !typeof(.closeCurlyBracket) {
                let key = try parseExpression()
                try expect(type: .colon, error: "Expected colon between key and value in object literal")
                let value = try parseExpression()
                values.append((key as! Expression, value as! Expression))
                if typeof(.comma) {
                    current += 1
                }
            }
            current += 1
            return ObjectLiteral(value: values)
        default:
            throw JinjaError.syntax("Unexpected token: \(token.type)")
        }
    }

    func parseExpressionSequence(primary: Bool = false) throws -> Statement {
        let fn = primary ? parsePrimaryExpression : parseExpression
        var expressions: [Expression] = try [fn() as! Expression]
        let isTuple = typeof(.comma)
        while isTuple {
            current += 1
            try expressions.append(fn() as! Expression)
            if !typeof(.comma) {
                break
            }
        }

        return isTuple ? TupleLiteral(value: expressions) : expressions[0]
    }

    func not(_ types: TokenType...) -> Bool {
        guard current + types.count <= tokens.count else {
            return false
        }

        return types.enumerated().contains { i, type -> Bool in
            type != tokens[current + i].type
        }
    }

    func parseForStatement() throws -> Statement {
        let loopVariable = try parseExpressionSequence(primary: true)

        if !(loopVariable is Identifier || loopVariable is TupleLiteral) {
            throw JinjaError.syntax(
                "Expected identifier/tuple for the loop variable, got \(type(of:loopVariable)) instead"
            )
        }

        try expect(type: .in, error: "Expected `in` keyword following loop variable")

        let iterable = try parseExpression()

        try expect(type: .closeStatement, error: "Expected closing statement token")

        var body: [Statement] = []
        while not(.openStatement, .endFor) {
            try body.append(parseAny())
        }

        if let loopVariable = loopVariable as? Loopvar {
            return For(loopvar: loopVariable, iterable: iterable as! Expression, body: body)
        }

        throw JinjaError.syntax(
            "Expected identifier/tuple for the loop variable, got \(type(of:loopVariable)) instead"
        )
    }

    func parseJinjaStatement() throws -> Statement {
        try expect(type: .openStatement, error: "Expected opening statement token")
        var result: Statement

        switch tokens[current].type {
        case .set:
            current += 1
            result = try parseSetStatement()
            try expect(type: .closeStatement, error: "Expected closing statement token")
        case .if:
            current += 1
            result = try parseIfStatement()
            try expect(type: .openStatement, error: "Expected {% token")
            try expect(type: .endIf, error: "Expected endif token")
            try expect(type: .closeStatement, error: "Expected %} token")
        case .for:
            current += 1
            result = try parseForStatement()
            try expect(type: .openStatement, error: "Expected {% token")
            try expect(type: .endFor, error: "Expected endfor token")
            try expect(type: .closeStatement, error: "Expected %} token")
        default:
            throw JinjaError.syntax("Unknown statement type: \(tokens[current].type)")
        }

        return result
    }

    func parseJinjaExpression() throws -> Statement {
        try expect(type: .openExpression, error: "Expected opening expression token")

        let result = try parseExpression()

        try expect(type: .closeExpression, error: "Expected closing expression token")

        return result
    }

    func parseAny() throws -> Statement {
        switch tokens[current].type {
        case .text:
            return try parseText()
        case .openStatement:
            return try parseJinjaStatement()
        case .openExpression:
            return try parseJinjaExpression()
        default:
            throw JinjaError.syntax("Unexpected token type: \(tokens[current].type)")
        }
    }

    while current < tokens.count {
        try program.body.append(parseAny())
    }

    return program
}
