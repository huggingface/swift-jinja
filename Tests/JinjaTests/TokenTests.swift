import Foundation
import Testing

@testable import Jinja

@Suite("Token Tests")
struct TokenTests {
    @Test("Initialization with String")
    func initWithString() {
        let token = Token(kind: .text, value: "hello", position: 0)
        #expect(token.kind == .text)
        #expect(token.value == "hello")
        #expect(token.position == 0)
    }

    @Test("Initialization with Substring")
    func initWithSubstring() {
        let source = "hello world"
        let substring = source.prefix(5)
        let token = Token(kind: .identifier, value: substring, position: 3)
        #expect(token.kind == .identifier)
        #expect(token.value == "hello")
        #expect(token.position == 3)
    }

    @Test("Kind CaseIterable")
    func kindCaseIterable() {
        let kinds = Token.Kind.allCases
        #expect(!kinds.isEmpty)
        #expect(kinds.contains(.text))
        #expect(kinds.contains(.identifier))
        #expect(kinds.contains(.openExpression))
        #expect(kinds.contains(.plus))
        #expect(kinds.contains(.minus))
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let token = Token(kind: .openExpression, value: "{{", position: 42)
        let encoder = JSONEncoder()
        let data = try encoder.encode(token)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Token.self, from: data)
        #expect(decoded.kind == token.kind)
        #expect(decoded.value == token.value)
        #expect(decoded.position == token.position)
    }

    @Test("Codable round-trip for Kind")
    func kindCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for kind in Token.Kind.allCases {
            let data = try encoder.encode(kind)
            let decoded = try decoder.decode(Token.Kind.self, from: data)
            #expect(decoded == kind)
        }
    }

    @Test("Equatable")
    func equatable() {
        let a = Token(kind: .text, value: "hello", position: 0)
        let b = Token(kind: .text, value: "hello", position: 0)
        let c = Token(kind: .text, value: "world", position: 0)
        let d = Token(kind: .identifier, value: "hello", position: 0)
        let e = Token(kind: .text, value: "hello", position: 5)
        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
        #expect(a != e)
    }

    @Test("Hashable")
    func hashable() {
        let a = Token(kind: .plus, value: "+", position: 10)
        let b = Token(kind: .plus, value: "+", position: 10)
        let c = Token(kind: .minus, value: "-", position: 10)
        var set: Set<Token> = [a, b]
        #expect(set.count == 1)
        set.insert(c)
        #expect(set.count == 2)
    }
}
