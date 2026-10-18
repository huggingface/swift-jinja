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

    @Test(
        "parser error names the unexpected token",
        arguments: [
            (
                "{{ name none }}",
                "Parser error: Expected '}}' after expression. Got 'none' (null) instead."
            ),
            (
                "{% if name }}yes{% endif %}",
                "Parser error: Expected '%}' after if condition. Got '}}' (closeExpression) instead."
            ),
            (
                "{{ name",
                "Parser error: Expected '}}' after expression. Got end of input instead."
            ),
            (
                "{{ {[1]: 2} }}",
                "Parser error: Expected string literal, identifier, or integer for object key. Got '[' (openBracket) instead."
            ),
        ]
    )
    func parserErrorNamesUnexpectedToken(source: String, description: String) {
        do {
            _ = try Template(source)
            Issue.record("Expected a parser error for \(source)")
        } catch {
            #expect(error.localizedDescription == description)
        }
    }
}
