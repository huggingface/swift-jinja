import Testing

@testable import Jinja

/// Integer arguments used as a count, width, index, or size
/// render as Jinja2 renders them, or throw instead of hanging or trapping.
/// The expected rendered strings come from jinja2 3.1.6.
@Suite("Argument bounds")
struct ArgumentBoundsTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let template: String
        let expected: String
        var testDescription: String { template }
    }

    static let renderedCases: [Case] = [
        Case(template: "{{ ''|wordwrap(0) }}", expected: ""),
        Case(template: "{{ 'ab'|indent(-2) }}", expected: "ab"),
        Case(template: "{{ 'a\\nb'|indent(-2, true) }}", expected: "a\nb"),
        Case(template: "{{ 'a'|truncate(9223372036854775807) }}", expected: "a"),
        Case(
            template: "{{ 'abcdefgh'|truncate(9223372036854775807, leeway=9223372036854775807) }}",
            expected: "abcdefgh"
        ),
        Case(template: "{{ 'abcdef'|truncate(0, end='') }}", expected: ""),
        Case(template: "{{ 'a'|center(-9223372036854775807 - 1) }}", expected: "a"),
        Case(template: "{{ 'a'|center(4) }}", expected: " a  "),
        Case(template: "{{ lipsum(-1) }}", expected: ""),
        Case(template: "{{ lipsum(1, min=-5, max=-1) }}", expected: "<p>.</p>"),
        Case(template: "{{ lipsum(0, min=5, max=1) }}", expected: ""),
        Case(
            template: "{{ 'www.x.com'|urlize(-1, rel='noopener') }}",
            expected: #"<a href="https://www.x.com" rel="noopener">www.x.co...</a>"#
        ),
        Case(
            template: "{{ 'www.x.com'|urlize(-100, rel='noopener') }}",
            expected: #"<a href="https://www.x.com" rel="noopener">...</a>"#
        ),
        Case(template: "{{ [1, 2, 3]|batch(2)|list }}", expected: "[[1, 2], [3]]"),
        Case(template: "{{ [1, 2, 3]|batch(2, 'x')|list }}", expected: "[[1, 2], [3, 'x']]"),
        Case(template: "{{ [1, 2, 3]|batch(9223372036854775807)|list }}", expected: "[[1, 2, 3]]"),
        Case(template: "{{ [1, 2, 3]|slice(-1)|list }}", expected: "[]"),
        Case(template: "{{ []|slice(-2, 'x')|list }}", expected: "[]"),
        Case(template: "{{ [1, 2, 3][:9223372036854775807] }}", expected: "[1, 2, 3]"),
        Case(template: "{{ [1, 2, 3][-9223372036854775807:] }}", expected: "[1, 2, 3]"),
        Case(template: "{{ [1, 2, 3][9223372036854775807::-1] }}", expected: "[3, 2, 1]"),
        Case(template: "{{ [1, 2, 3, 4, 5][-10::-1] }}", expected: "[]"),
        Case(template: "{{ 'abc'[:9223372036854775807] }}", expected: "abc"),
        Case(template: "{{ 'abc'[-9223372036854775807:] }}", expected: "abc"),
        Case(template: "{{ 'abc'[9223372036854775807::-1] }}", expected: "cba"),
        Case(template: "{{ 'abc'[:-9223372036854775807:-1] }}", expected: "cba"),
        Case(template: "{{ 'hello'[-100:100] }}", expected: "hello"),
        Case(template: "{{ 'aaa'.replace('a', 'aa', 9223372036854775807) }}", expected: "aaaaaa"),
        Case(template: "{{ 'a'.replace('a', 'aa', 2) }}", expected: "aa"),
        Case(template: "{{ 'abc'|replace('b', 'x', -1) }}", expected: "axc"),
        Case(template: "{{ 'abc'|replace('', '-', -1) }}", expected: "-a-b-c-"),
        Case(template: "{{ (-9223372036854775807 - 1) is divisibleby(-1) }}", expected: "True"),
        Case(template: "{{ range(1, 9223372036854775807, 9223372036854775807)|list }}", expected: "[1]"),
        Case(
            template: "{{ range(-2, -9223372036854775807 - 1, -9223372036854775807)|list }}",
            expected: "[-2]"
        ),
    ]

    /// Jinja2 raises or renders something that swift-jinja can't;
    /// the comment gives Jinja2's result.
    static let rejectedCases: [Case] = [
        // ValueError: invalid width 0 (must be > 0)
        Case(template: "{{ 'a b'|wordwrap(0) }}", expected: "invalid width 0 (must be > 0)"),
        // ValueError: invalid width -1 (must be > 0)
        Case(template: "{{ 'a b'|wordwrap(-1) }}", expected: "invalid width -1 (must be > 0)"),
        // AssertionError: expected length >= 3, got -1
        Case(template: "{{ 'abcdef'|truncate(-1) }}", expected: "expected length >= 3, got -1"),
        // AssertionError: expected length >= 3, got 2
        Case(template: "{{ 'abcdef'|truncate(2) }}", expected: "expected length >= 3, got 2"),
        // 9223372036854775808
        Case(
            template: "{{ (-9223372036854775807 - 1)|abs }}",
            expected: "Integer overflow in abs(-9223372036854775808)"
        ),
        // ValueError: empty range in randrange(5, 1)
        Case(template: "{{ lipsum(1, min=5, max=1) }}", expected: "empty range in randrange(5, 1)"),
        // ValueError: empty range in randrange(5, 5)
        Case(template: "{{ lipsum(1, min=5, max=5) }}", expected: "empty range in randrange(5, 5)"),
        // MemoryError
        Case(
            template: "{{ 'a' * 9223372036854775807 }}",
            expected: "Repeating a string 9223372036854775807 times exceeds the limit of 268435456 bytes"
        ),
        // MemoryError
        Case(
            template: "{{ 9223372036854775807 * 'a' }}",
            expected: "Repeating a string 9223372036854775807 times exceeds the limit of 268435456 bytes"
        ),
        // 'ab' repeated 134217729 times, 268435458 bytes
        Case(
            template: "{{ 'ab' * 134217729 }}",
            expected: "Repeating a string 134217729 times exceeds the limit of 268435456 bytes"
        ),
        // MemoryError
        Case(
            template: "{{ 'a'|center(9223372036854775807) }}",
            expected: "Repeating a string 9223372036854775806 times exceeds the limit of 268435456 bytes"
        ),
        // 'a' centered in 268435458 spaces
        Case(
            template: "{{ 'a'|center(268435458) }}",
            expected: "Repeating a string 268435457 times exceeds the limit of 268435456 bytes"
        ),
        // MemoryError
        Case(
            template: "{{ 'a'|indent(9223372036854775807) }}",
            expected: "Repeating a string 9223372036854775807 times exceeds the limit of 268435456 bytes"
        ),
        // MemoryError
        Case(
            template: "{{ [1]|tojson(indent=9223372036854775807) }}",
            expected: "Repeating a string 9223372036854775807 times exceeds the limit of 268435456 bytes"
        ),
        // MemoryError
        Case(
            template: "{{ [1, 2, 3]|batch(9223372036854775807, 'x')|list }}",
            expected: "Repeating a value 9223372036854775804 times exceeds the limit of 268435456 bytes"
        ),
        // Doesn't finish: Jinja2 yields 9223372036854775807 lists.
        Case(
            template: "{{ [1, 2, 3]|slice(9223372036854775807)|list }}",
            expected: "Repeating a value 9223372036854775807 times exceeds the limit of 268435456 bytes"
        ),
    ]

    @Test(arguments: renderedCases)
    func matchesJinja2(_ c: Case) throws {
        let rendered = try Template(c.template).render([:])
        #expect(rendered == c.expected)
    }

    @Test(arguments: rejectedCases)
    func throwsRuntimeError(_ c: Case) throws {
        do {
            let rendered = try Template(c.template).render([:])
            Issue.record("Expected a runtime error for \(c.template); rendered \(rendered)")
        } catch JinjaError.runtime(let message) {
            #expect(message == c.expected)
        }
    }
}
