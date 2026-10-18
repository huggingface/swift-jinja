import Testing

@testable import Jinja

/// Integer literals that fit in `Int` render as Jinja2 renders them.
/// Jinja2 uses Python integers, so it also accepts larger literals;
/// swift-jinja has no arbitrary-precision integers,
/// so it throws a parser error instead of substituting another value.
/// The expected rendered strings come from jinja2 3.1.6.
@Suite("Integer literals")
struct IntegerLiteralTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let template: String
        let expected: String
        var testDescription: String { template }
    }

    static let renderedCases: [Case] = [
        Case(template: "{{ 9223372036854775807 }}", expected: "9223372036854775807"),
        Case(template: "{{ -9223372036854775807 }}", expected: "-9223372036854775807"),
        Case(template: "{{ -9223372036854775807 - 1 }}", expected: "-9223372036854775808"),
        Case(template: "{{ [1, 2][0] }}", expected: "1"),
        Case(template: "{{ foo[0] }}", expected: "10"),
        Case(template: "{{ foo[1:] }}", expected: "[20]"),
        Case(template: "{{ foo[:1] }}", expected: "[10]"),
        Case(template: "{{ foo[::-1] }}", expected: "[20, 10]"),
        Case(template: "{{ 99999999999999999999.5 }}", expected: "1e+20"),
    ]

    static let rejectedCases: [Case] = [
        Case(
            template: "{{ 99999999999999999999 }}",
            expected: "Integer literal '99999999999999999999' is too large."
        ),
        Case(
            template: "{{ 9223372036854775808 }}",
            expected: "Integer literal '9223372036854775808' is too large."
        ),
        // Unary minus applies to the literal after it is parsed,
        // so the literal `9223372036854775808` must fit in `Int` on its own.
        Case(
            template: "{{ -9223372036854775808 }}",
            expected: "Integer literal '9223372036854775808' is too large."
        ),
        Case(
            template: "{{ foo[99999999999999999999] }}",
            expected: "Integer literal '99999999999999999999' is too large."
        ),
        Case(
            template: "{{ foo[99999999999999999999:] }}",
            expected: "Integer literal '99999999999999999999' is too large."
        ),
        Case(
            template: "{{ foo[1:99999999999999999999] }}",
            expected: "Integer literal '99999999999999999999' is too large."
        ),
        Case(
            template: "{{ foo[::99999999999999999999] }}",
            expected: "Integer literal '99999999999999999999' is too large."
        ),
        Case(
            template: "{{ range(99999999999999999998, 99999999999999999999)|list }}",
            expected: "Integer literal '99999999999999999998' is too large."
        ),
        Case(
            template: "{{ 99999999999999999999 - 99999999999999999998 }}",
            expected: "Integer literal '99999999999999999999' is too large."
        ),
        Case(
            template: "{{ {99999999999999999999: 'a'}[99999999999999999999] }}",
            expected: "Integer literal '99999999999999999999' is too large."
        ),
        Case(
            template: "{{ foo.99999999999999999999 }}",
            expected: "Integer literal '99999999999999999999' is too large."
        ),
        Case(
            template: "{{ \u{00B2} }}",
            expected: "Invalid integer literal '\u{00B2}'."
        ),
        Case(
            template: "{{ 1.\u{00B2} }}",
            expected: "Invalid number literal '1.\u{00B2}'."
        ),
    ]

    @Test(arguments: renderedCases)
    func matchesJinja2(_ c: Case) throws {
        let rendered = try Template(c.template).render(["foo": [10, 20]])
        #expect(rendered == c.expected)
    }

    @Test(arguments: rejectedCases)
    func throwsParserError(_ c: Case) throws {
        do {
            _ = try Template(c.template)
            Issue.record("Expected a parser error for \(c.template)")
        } catch JinjaError.parser(let message) {
            #expect(message == c.expected)
        }
    }
}
