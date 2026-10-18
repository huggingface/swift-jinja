import Testing

@testable import Jinja

/// Arithmetic near the limits of `Int` and conversions from doubles to integers
/// render as Jinja2 renders them, or throw instead of trapping.
/// Jinja2 uses Python integers, which have arbitrary precision;
/// swift-jinja has no arbitrary-precision integers,
/// so it throws a runtime error where the result doesn't fit in `Int`.
/// The expected rendered strings come from jinja2 3.1.6.
@Suite("Arithmetic overflow")
struct ArithmeticOverflowTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let template: String
        var context: [String: Value] = [:]
        let expected: String
        var testDescription: String { "\(template) \(context)" }
    }

    static let renderedCases: [Case] = [
        Case(template: "{{ 'ab' * -1 }}", expected: ""),
        Case(template: "{{ -1 * 'ab' }}", expected: ""),
        Case(template: "{{ 'ab' * 0 }}", expected: ""),
        Case(template: "{{ 9223372036854775806 + 1 }}", expected: "9223372036854775807"),
        Case(template: "{{ -9223372036854775807 - 1 }}", expected: "-9223372036854775808"),
        Case(template: "{{ 3037000499 * 3037000499 }}", expected: "9223372030926249001"),
        Case(template: "{{ 2 ** 62 }}", expected: "4611686018427387904"),
        Case(template: "{{ 3 ** 39 }}", expected: "4052555153018976267"),
        Case(template: "{{ (-2) ** 63 }}", expected: "-9223372036854775808"),
        Case(template: "{{ 0 ** 0 }}", expected: "1"),
        Case(template: "{{ 1 ** 100000 }}", expected: "1"),
        Case(template: "{{ (-1) ** 100001 }}", expected: "-1"),
        Case(template: "{{ (-9223372036854775807 - 1) % -1 }}", expected: "0"),
        // Python's `int()` raises `ValueError` for NaN, so Jinja2 returns the default.
        Case(template: "{{ x | int }}", context: ["x": .double(.nan)], expected: "0"),
        Case(template: "{{ x | int(7) }}", context: ["x": .double(.nan)], expected: "7"),
        Case(template: "{{ x | int }}", context: ["x": .double(9.2e18)], expected: "9200000000000000000"),
        Case(template: "{{ x | int }}", context: ["x": .double(-3.7)], expected: "-3"),
        Case(template: "{{ x | filesizeformat }}", context: ["x": .double(.infinity)], expected: "inf YB"),
        Case(template: "{{ x | filesizeformat }}", context: ["x": .double(.nan)], expected: "nan YB"),
        Case(template: "{{ x | filesizeformat(true) }}", context: ["x": .double(.infinity)], expected: "inf YiB"),
    ]

    /// Jinja2 renders each of these templates; the comment gives its output.
    static let rejectedCases: [Case] = [
        // 9223372036854775808
        Case(
            template: "{{ 9223372036854775807 + 1 }}",
            expected: "Integer overflow in 9223372036854775807 + 1"
        ),
        // -9223372036854775809
        Case(
            template: "{{ -9223372036854775807 - 2 }}",
            expected: "Integer overflow in -9223372036854775807 - 2"
        ),
        // 18446744073709551614
        Case(
            template: "{{ 9223372036854775807 * 2 }}",
            expected: "Integer overflow in 9223372036854775807 * 2"
        ),
        // 9223372036854775808
        Case(
            template: "{{ -(-9223372036854775807 - 1) }}",
            expected: "Integer overflow in -(-9223372036854775808)"
        ),
        // 9223372036854775808
        Case(template: "{{ 2 ** 63 }}", expected: "Integer overflow in 2 ** 63"),
        // 18446744073709551616
        Case(template: "{{ 2 ** 64 }}", expected: "Integer overflow in 2 ** 64"),
        // 1 followed by 100 zeros
        Case(template: "{{ 10 ** 100 }}", expected: "Integer overflow in 10 ** 100"),
        // 9223372036854775808
        Case(
            template: "{{ (-9223372036854775807 - 1) // -1 }}",
            expected: "Integer overflow in -9223372036854775808 // -1"
        ),
        // 1e+300
        Case(
            template: "{{ x // 1 }}",
            context: ["x": .double(1e300)],
            expected: "Cannot convert 1e+300 to an integer"
        ),
        // 9.999999999999999e+299
        Case(
            template: "{{ 1 // x }}",
            context: ["x": .double(1e-300)],
            expected: "Cannot convert 9.999999999999999e+299 to an integer"
        ),
        // nan
        Case(
            template: "{{ x // 2 }}",
            context: ["x": .double(.nan)],
            expected: "Cannot convert nan to an integer"
        ),
        // OverflowError: cannot convert float infinity to integer
        Case(
            template: "{{ x | int }}",
            context: ["x": .double(.infinity)],
            expected: "Cannot convert inf to an integer"
        ),
        // 10000000000000000000
        Case(
            template: "{{ x | int }}",
            context: ["x": .double(1e19)],
            expected: "Cannot convert 1e+19 to an integer"
        ),
        // OverflowError: cannot convert float infinity to integer
        Case(
            template: "{{ x | filesizeformat }}",
            context: ["x": .double(-.infinity)],
            expected: "Cannot convert -inf to an integer"
        ),
    ]

    @Test(arguments: renderedCases)
    func matchesJinja2(_ c: Case) throws {
        let rendered = try Template(c.template).render(c.context)
        #expect(rendered == c.expected)
    }

    @Test(arguments: rejectedCases)
    func throwsRuntimeError(_ c: Case) throws {
        do {
            let rendered = try Template(c.template).render(c.context)
            Issue.record("Expected a runtime error for \(c.template); rendered \(rendered)")
        } catch JinjaError.runtime(let message) {
            #expect(message == c.expected)
        }
    }
}
