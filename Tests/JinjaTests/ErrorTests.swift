import Foundation
import Testing

@testable import Jinja

@Suite("Error Tests")
struct ErrorTests {
    @Test("lexer error description")
    func lexerErrorDescription() {
        let error = JinjaError.lexer("unexpected token")
        #expect(error.errorDescription == "Lexer error: unexpected token")
    }

    @Test("parser error description")
    func parserErrorDescription() {
        let error = JinjaError.parser("unexpected end of input")
        #expect(error.errorDescription == "Parser error: unexpected end of input")
    }

    @Test("runtime error description")
    func runtimeErrorDescription() {
        let error = JinjaError.runtime("undefined variable")
        #expect(error.errorDescription == "Runtime error: undefined variable")
    }

    @Test("syntax error description")
    func syntaxErrorDescription() {
        let error = JinjaError.syntax("invalid expression")
        #expect(error.errorDescription == "Syntax error: invalid expression")
    }
}
