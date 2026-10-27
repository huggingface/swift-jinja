import Foundation
import Testing

@testable import Jinja

/// Token positions count characters (extended grapheme clusters)
/// from the start of the source,
/// not bytes or Unicode scalars.
@Suite("Lexer positions")
struct LexerPositionTests {
    @Test("ASCII")
    func ascii() throws {
        let tokens = try Lexer.tokenize("Hello {{ name }}!")
        #expect(
            tokens == [
                Token(kind: .text, value: "Hello ", position: 0),
                Token(kind: .openExpression, value: "{{", position: 6),
                Token(kind: .identifier, value: "name", position: 9),
                Token(kind: .closeExpression, value: "}}", position: 14),
                Token(kind: .text, value: "!", position: 16),
                Token(kind: .eof, value: "", position: 17),
            ]
        )
    }

    @Test("Multi-byte UTF-8 characters")
    func multiByte() throws {
        let tokens = try Lexer.tokenize("café 日本 {{ 'ü' ~ x }} ñ")
        #expect(
            tokens == [
                Token(kind: .text, value: "café 日本 ", position: 0),
                Token(kind: .openExpression, value: "{{", position: 8),
                Token(kind: .string, value: "ü", position: 11),
                Token(kind: .concat, value: "~", position: 15),
                Token(kind: .identifier, value: "x", position: 17),
                Token(kind: .closeExpression, value: "}}", position: 19),
                Token(kind: .text, value: " ñ", position: 21),
                Token(kind: .eof, value: "", position: 23),
            ]
        )
    }

    @Test("Characters with several Unicode scalars")
    func multiScalarCharacters() throws {
        // A family emoji joined with zero-width joiners,
        // a decomposed "é", and a flag each count as one character.
        let tokens = try Lexer.tokenize("👨‍👩‍👧e\u{301}🇺🇸{{ x }}🇺🇸")
        #expect(
            tokens == [
                Token(kind: .text, value: "👨‍👩‍👧e\u{301}🇺🇸", position: 0),
                Token(kind: .openExpression, value: "{{", position: 3),
                Token(kind: .identifier, value: "x", position: 6),
                Token(kind: .closeExpression, value: "}}", position: 8),
                Token(kind: .text, value: "🇺🇸", position: 10),
                Token(kind: .eof, value: "", position: 11),
            ]
        )
    }

    @Test("Characters with several Unicode scalars in a tag")
    func multiScalarCharactersInTag() throws {
        let tokens = try Lexer.tokenize("{{ '👨‍👩‍👧' ~ y }}")
        #expect(
            tokens == [
                Token(kind: .openExpression, value: "{{", position: 0),
                Token(kind: .string, value: "👨‍👩‍👧", position: 3),
                Token(kind: .concat, value: "~", position: 7),
                Token(kind: .identifier, value: "y", position: 9),
                Token(kind: .closeExpression, value: "}}", position: 11),
                Token(kind: .eof, value: "", position: 13),
            ]
        )
    }

    @Test("CRLF and lone CR line endings")
    func lineEndings() throws {
        // "\r\n" is one character; a lone "\r" is one character.
        let tokens = try Lexer.tokenize("a\r\n{{ x }}\r\nb\rc{{ y }}")
        #expect(
            tokens == [
                Token(kind: .text, value: "a\r\n", position: 0),
                Token(kind: .openExpression, value: "{{", position: 2),
                Token(kind: .identifier, value: "x", position: 5),
                Token(kind: .closeExpression, value: "}}", position: 7),
                Token(kind: .text, value: "\r\nb\rc", position: 9),
                Token(kind: .openExpression, value: "{{", position: 13),
                Token(kind: .identifier, value: "y", position: 16),
                Token(kind: .closeExpression, value: "}}", position: 18),
                Token(kind: .eof, value: "", position: 20),
            ]
        )
    }

    @Test("CRLF and lone CR line endings in a tag")
    func lineEndingsInTag() throws {
        let tokens = try Lexer.tokenize("{{\r\nx\r}}")
        #expect(
            tokens == [
                Token(kind: .openExpression, value: "{{", position: 0),
                Token(kind: .identifier, value: "x", position: 3),
                Token(kind: .closeExpression, value: "}}", position: 5),
                Token(kind: .eof, value: "", position: 7),
            ]
        )
    }

    @Test("Whitespace control delimiters")
    func whitespaceControl() throws {
        // Trimmed whitespace still counts toward the positions after it.
        let tokens = try Lexer.tokenize("é \r\n{%- if x -%}\r\n 👍 {%- endif %}")
        #expect(
            tokens == [
                Token(kind: .text, value: "é", position: 0),
                Token(kind: .openStatement, value: "{%-", position: 3),
                Token(kind: .if, value: "if", position: 7),
                Token(kind: .identifier, value: "x", position: 10),
                Token(kind: .closeStatement, value: "-%}", position: 12),
                Token(kind: .text, value: "👍", position: 17),
                Token(kind: .openStatement, value: "{%-", position: 19),
                Token(kind: .endif, value: "endif", position: 23),
                Token(kind: .closeStatement, value: "%}", position: 29),
                Token(kind: .eof, value: "", position: 31),
            ]
        )
    }

    @Test("Long template")
    func longTemplate() throws {
        // Each segment is 11 characters:
        // "é", the family emoji, " ", "{{ x }}", and "\r\n".
        let segment = "é👨‍👩‍👧 {{ x }}\r\n"
        let segmentLength = 11
        let repetitions = 2_000
        let source = String(repeating: segment, count: repetitions)
        #expect(source.count == segmentLength * repetitions)

        var expected = [Token(kind: .text, value: "é👨‍👩‍👧 ", position: 0)]
        for i in 0 ..< repetitions {
            let start = i * segmentLength
            expected.append(Token(kind: .openExpression, value: "{{", position: start + 3))
            expected.append(Token(kind: .identifier, value: "x", position: start + 6))
            expected.append(Token(kind: .closeExpression, value: "}}", position: start + 8))
            let text = i == repetitions - 1 ? "\r\n" : "\r\né👨‍👩‍👧 "
            expected.append(Token(kind: .text, value: text, position: start + 10))
        }
        expected.append(Token(kind: .eof, value: "", position: segmentLength * repetitions))

        let tokens = try Lexer.tokenize(source)
        #expect(tokens.count == expected.count)
        for (token, expectedToken) in zip(tokens, expected) where token != expectedToken {
            Issue.record("Expected \(expectedToken), got \(token)")
            break
        }
    }

    struct TokenCase: CustomTestStringConvertible, Sendable {
        let source: String
        let expected: [Token]
        var testDescription: String { source.debugDescription }
    }

    static let tokenCases: [TokenCase] = [
        // Comments
        TokenCase(
            source: "é{#- c -#}\r\n{{x}}",
            expected: [
                Token(kind: .text, value: "é", position: 0),
                Token(kind: .comment, value: " c ", position: 1),
                Token(kind: .openExpression, value: "{{", position: 11),
                Token(kind: .identifier, value: "x", position: 13),
                Token(kind: .closeExpression, value: "}}", position: 14),
                Token(kind: .eof, value: "", position: 16),
            ]
        ),
        TokenCase(
            source: "{# 日本 #}{{ x }}",
            expected: [
                Token(kind: .comment, value: " 日本 ", position: 0),
                Token(kind: .openExpression, value: "{{", position: 8),
                Token(kind: .identifier, value: "x", position: 11),
                Token(kind: .closeExpression, value: "}}", position: 13),
                Token(kind: .eof, value: "", position: 15),
            ]
        ),
        TokenCase(
            source: "👨‍👩‍👧{# c #}\r\nx",
            expected: [
                Token(kind: .text, value: "👨‍👩‍👧", position: 0),
                Token(kind: .comment, value: " c ", position: 1),
                Token(kind: .text, value: "\r\nx", position: 8),
                Token(kind: .eof, value: "", position: 10),
            ]
        ),
        TokenCase(
            source: "é {#- c #}x",
            expected: [
                Token(kind: .text, value: "é", position: 0),
                Token(kind: .comment, value: " c ", position: 2),
                Token(kind: .text, value: "x", position: 10),
                Token(kind: .eof, value: "", position: 11),
            ]
        ),
        // A combining mark beside an opening delimiter
        TokenCase(
            source: "a\u{301}{{ x }}",
            expected: [
                Token(kind: .text, value: "a\u{301}", position: 0),
                Token(kind: .openExpression, value: "{{", position: 1),
                Token(kind: .identifier, value: "x", position: 4),
                Token(kind: .closeExpression, value: "}}", position: 6),
                Token(kind: .eof, value: "", position: 8),
            ]
        ),
        // A combining mark joins the brace before it into one character,
        // so the delimiter is text.
        TokenCase(
            source: "{\u{301}{ x }}",
            expected: [
                Token(kind: .text, value: "{\u{301}{ x }}", position: 0),
                Token(kind: .eof, value: "", position: 7),
            ]
        ),
        TokenCase(
            source: "{{\u{301} x }}",
            expected: [
                Token(kind: .text, value: "{{\u{301} x }}", position: 0),
                Token(kind: .eof, value: "", position: 7),
            ]
        ),
        TokenCase(
            source: "{#\u{301} c #}x",
            expected: [
                Token(kind: .text, value: "{#\u{301} c #}x", position: 0),
                Token(kind: .eof, value: "", position: 8),
            ]
        ),
    ]

    @Test("Positions of comments and of delimiters beside combining marks", arguments: tokenCases)
    func tokenPositions(_ c: TokenCase) throws {
        #expect(try Lexer.tokenize(c.source) == c.expected)
    }

    struct ErrorCase: CustomTestStringConvertible, Sendable {
        let source: String
        let message: String
        var testDescription: String { source.debugDescription }
    }

    static let errorCases: [ErrorCase] = [
        // Unexpected characters
        ErrorCase(source: "é{{ @ }}", message: "Unexpected character '@' at position 4"),
        ErrorCase(source: "👨‍👩‍👧\r\n{{ x $ }}", message: "Unexpected character '$' at position 7"),
        ErrorCase(source: "{{ 'ü' ~ ? }}", message: "Unexpected character '?' at position 9"),
        // Unclosed strings
        ErrorCase(source: "é{{ 'abc", message: "Unclosed string at position 4"),
        ErrorCase(source: "👨‍👩‍👧\r\n{{ \"日本 }}", message: "Unclosed string at position 5"),
        // Unclosed comments
        ErrorCase(source: "é{# abc", message: "Unclosed comment at position 1"),
        ErrorCase(source: "\r\n👨‍👩‍👧{# 日本 #", message: "Unclosed comment at position 2"),
        // A combining mark after a closing brace joins it into one character.
        ErrorCase(source: "{{ x }}\u{301}y", message: "Unexpected character '}\u{301}' at position 6"),
        ErrorCase(source: "{{ x }\u{301}}", message: "Unexpected character '}\u{301}' at position 5"),
        ErrorCase(
            source: "{% if x %}\u{301}{% endif %}",
            message: "Unexpected character '}\u{301}' at position 9"
        ),
    ]

    @Test("Positions in lexer errors", arguments: errorCases)
    func errorPositions(_ c: ErrorCase) {
        do {
            let tokens = try Lexer.tokenize(c.source)
            Issue.record("Expected an error, got \(tokens)")
        } catch JinjaError.lexer(let message) {
            #expect(message == c.message)
        } catch {
            Issue.record("Expected a lexer error, got \(error)")
        }
    }

    /// Lexing a large template finishes well within a generous time limit.
    /// This guards against a large slowdown, such as counting each position
    /// from the start of the source, which took about 30 seconds
    /// for this template in a debug build;
    /// counting from the previous token takes less than a tenth of a second.
    /// It doesn't measure how lexing time grows with the length of the source.
    @Test("Lexing a large template finishes within a time limit")
    func largeTemplateTimeout() throws {
        let source = String(repeating: "é👨‍👩‍👧 {{ x }}\r\n", count: 10_000)
        var tokens: [Token] = []
        let duration = try ContinuousClock().measure {
            tokens = try Lexer.tokenize(source)
        }
        #expect(tokens.last == Token(kind: .eof, value: "", position: 110_000))
        #expect(duration < .seconds(5))
    }
}
