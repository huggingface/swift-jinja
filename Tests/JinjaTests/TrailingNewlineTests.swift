import Testing

@testable import Jinja

/// By default, a single newline at the end of the template source is removed,
/// as Jinja2 does with `keep_trailing_newline=False`.
/// `keepTrailingNewline` keeps it.
/// Expected strings were rendered with jinja2 3.1.6.
@Suite("Trailing newline")
struct TrailingNewlineTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let template: String
        var context: [String: Value] = [:]
        let defaults: String
        let kept: String
        let trimmedAndLstripped: String
        let keptTrimmedAndLstripped: String
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(
            name: "empty template",
            template: "",
            defaults: "",
            kept: "",
            trimmedAndLstripped: "",
            keptTrimmedAndLstripped: ""
        ),
        Case(
            name: "only a newline",
            template: "\n",
            defaults: "",
            kept: "\n",
            trimmedAndLstripped: "",
            keptTrimmedAndLstripped: "\n"
        ),
        Case(
            name: "no trailing newline",
            template: "no\nnewline",
            defaults: "no\nnewline",
            kept: "no\nnewline",
            trimmedAndLstripped: "no\nnewline",
            keptTrimmedAndLstripped: "no\nnewline"
        ),
        Case(
            name: "text and a newline",
            template: "with\nnewline\n",
            defaults: "with\nnewline",
            kept: "with\nnewline\n",
            trimmedAndLstripped: "with\nnewline",
            keptTrimmedAndLstripped: "with\nnewline\n"
        ),
        Case(
            name: "only one of several newlines is removed",
            template: "with\nseveral\n\n\n",
            defaults: "with\nseveral\n\n",
            kept: "with\nseveral\n\n\n",
            trimmedAndLstripped: "with\nseveral\n\n",
            keptTrimmedAndLstripped: "with\nseveral\n\n\n"
        ),
        Case(
            name: "expression and a newline",
            template: "{{ 'a' }}\n",
            defaults: "a",
            kept: "a\n",
            trimmedAndLstripped: "a",
            keptTrimmedAndLstripped: "a\n"
        ),
        Case(
            name: "newline from a variable is kept",
            template: "{{ x }}",
            context: ["x": "a\n"],
            defaults: "a\n",
            kept: "a\n",
            trimmedAndLstripped: "a\n",
            keptTrimmedAndLstripped: "a\n"
        ),
        Case(
            name: "block and a newline",
            template: "{% if true %}x{% endif %}\n",
            defaults: "x",
            kept: "x\n",
            trimmedAndLstripped: "x",
            keptTrimmedAndLstripped: "x"
        ),
        Case(
            name: "block, a newline, and a blank line",
            template: "{% if true %}x{% endif %}\n\n",
            defaults: "x\n",
            kept: "x\n\n",
            trimmedAndLstripped: "x",
            keptTrimmedAndLstripped: "x\n"
        ),
        Case(
            name: "indented blocks",
            template: "  {% if true %}\n  x\n  {% endif %}\n",
            defaults: "  \n  x\n  ",
            kept: "  \n  x\n  \n",
            trimmedAndLstripped: "  x\n",
            keptTrimmedAndLstripped: "  x\n"
        ),
        Case(
            name: "dash before the newline",
            template: "{{ 'a' -}}\n",
            defaults: "a",
            kept: "a",
            trimmedAndLstripped: "a",
            keptTrimmedAndLstripped: "a"
        ),
    ]

    @Test(arguments: cases)
    func matchesJinja2WithDefaultOptions(_ c: Case) throws {
        let rendered = try Template(c.template).render(c.context)
        #expect(rendered == c.defaults)
    }

    @Test(arguments: cases)
    func matchesJinja2WithKeepTrailingNewline(_ c: Case) throws {
        let rendered = try Template(c.template, with: .init(keepTrailingNewline: true)).render(c.context)
        #expect(rendered == c.kept)
    }

    @Test(arguments: cases)
    func matchesJinja2WithTrimAndLstripBlocks(_ c: Case) throws {
        let rendered = try Template(c.template, with: .init(lstripBlocks: true, trimBlocks: true)).render(c.context)
        #expect(rendered == c.trimmedAndLstripped)
    }

    @Test(arguments: cases)
    func matchesJinja2WithKeepTrailingNewlineAndTrimAndLstripBlocks(_ c: Case) throws {
        let options = Template.Options(lstripBlocks: true, trimBlocks: true, keepTrailingNewline: true)
        let rendered = try Template(c.template, with: options).render(c.context)
        #expect(rendered == c.keptTrimmedAndLstripped)
    }

    /// Jinja2 treats `\r\n` and `\r` as line breaks too.
    @Test(
        arguments: [
            ("abc\r\n", "abc"),
            ("abc\r", "abc"),
            ("a\n\r", "a\n"),
        ]
    )
    func removesOtherLineBreaks(template: String, expected: String) throws {
        #expect(try Template(template).render([:]) == expected)
        #expect(try Template(template, with: .init(lstripBlocks: true, trimBlocks: true)).render([:]) == expected)
    }
}
