//
//  Ast.swift
//
//
//  Created by John Mai on 2024/3/20.
//

import Foundation

protocol Statement {}

struct Program: Statement {
    var body: [Statement] = []
}

protocol Expression: Statement {}

protocol Literal: Expression {
    associatedtype T
    var value: T { get set }
}

struct StringLiteral: Literal {
    var value: String
}

struct NumericLiteral: Literal {
    var value: any Numeric
}

struct BoolLiteral: Literal {
    var value: Bool
}

struct ArrayLiteral: Literal {
    var value: [Expression]
}

struct TupleLiteral: Literal {
    var value: [Expression]
}

struct ObjectLiteral: Literal {
    var value: [(Expression, Expression)]
}

struct Set: Statement {
    var assignee: Expression
    var value: Expression
}

struct If: Statement {
    var test: Expression
    var body: [Statement]
    var alternate: [Statement]
}

struct Identifier: Expression {
    var value: String
}

protocol Loopvar {}
extension Identifier: Loopvar {}
extension TupleLiteral: Loopvar {}

struct For: Statement {
    var loopvar: Loopvar
    var iterable: Expression
    var body: [Statement]
    var defaultBlock: [Statement]
}

struct MemberExpression: Expression {
    var object: Expression
    var property: Expression
    var computed: Bool
}

struct CallExpression: Expression {
    var callee: Expression
    var args: [Expression]
}

struct BinaryExpression: Expression {
    var operation: Token
    var left: Expression
    var right: Expression
}

protocol Filter {}
extension Identifier: Filter {}
extension CallExpression: Filter {}

struct FilterExpression: Expression {
    var operand: Expression
    var filter: Filter
}

struct TestExpression: Expression {
    var operand: Expression
    var negate: Bool
    var test: Identifier
}

struct UnaryExpression: Expression {
    var operation: Token
    var argument: Expression
}

struct LogicalNegationExpression: Expression {
    var argument: Expression
}

struct SliceExpression: Expression {
    var start: Expression?
    var stop: Expression?
    var step: Expression?
}

struct KeywordArgumentExpression: Expression {
    var key: Identifier
    var value: any Expression
}

struct NullLiteral: Literal {
    var value: Any? = nil
}

struct SelectExpression: Expression {
    var iterable: Expression
    var test: Expression
}

struct Macro: Statement {
    var name: Identifier
    var args: [Expression]
    var body: [Statement]
}

struct KeywordArgumentsValue: RuntimeValue {
    var value: [String: any RuntimeValue]
    var builtins: [String: any RuntimeValue] = [:]

    func bool() -> Bool {
        !value.isEmpty
    }
}
