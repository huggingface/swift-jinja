import Testing

@testable import Jinja

/// `{{-`, `{%-`, and `{#-` strip the whitespace before a tag,
/// and `-}}`, `-%}`, and `-#}` strip the whitespace after it.
/// Expected strings were rendered with jinja2 3.1.6.
@Suite("Whitespace control")
struct WhitespaceControlTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let template: String
        let defaults: String
        let trimmedAndLstripped: String
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(
            name: "dash close in a string",
            template: "{{ \"a -}} b\" }}",
            defaults: "a -}} b",
            trimmedAndLstripped: "a -}} b"
        ),
        Case(
            name: "dash close in a statement string",
            template: "{% set x = 'a -%} b' %}{{ x }}",
            defaults: "a -%} b",
            trimmedAndLstripped: "a -%} b"
        ),
        Case(
            name: "dash comment close in a string",
            template: "{{ 'a -#} b' }}",
            defaults: "a -#} b",
            trimmedAndLstripped: "a -#} b"
        ),
        Case(
            name: "brace before a dashed statement",
            template: "{\n{%- if true %}x{% endif %}",
            defaults: "{x",
            trimmedAndLstripped: "{x"
        ),
        Case(
            name: "brace before a dashed expression",
            template: "{ {{- 'x' }}",
            defaults: "{x",
            trimmedAndLstripped: "{x"
        ),
        Case(
            name: "brace before a dashed comment",
            template: "{\n{#- c #}x",
            defaults: "{x",
            trimmedAndLstripped: "{x"
        ),
        Case(
            name: "leading whitespace before a dashed statement",
            template: "  \n  {%- if true %}x{% endif %}",
            defaults: "x",
            trimmedAndLstripped: "x"
        ),
        Case(
            name: "dashes on both sides of an expression",
            template: "a \n {{- 'b' -}} \n c",
            defaults: "abc",
            trimmedAndLstripped: "abc"
        ),
        Case(
            name: "dashes on both sides of a statement",
            template: "a \n {%- if true -%} \n b \n {%- endif -%} \n c",
            defaults: "abc",
            trimmedAndLstripped: "abc"
        ),
        Case(
            name: "dash close strips to the next text only",
            template: "{{ 'a' -}}\n\n  b  {{ 'c' }}",
            defaults: "ab  c",
            trimmedAndLstripped: "ab  c"
        ),
        Case(
            name: "Unicode whitespace",
            template: "a\u{3000}\u{A0}\u{2028}{{- 'b' -}}\u{85}\u{2003}c",
            defaults: "abc",
            trimmedAndLstripped: "abc"
        ),
        Case(
            name: "information separators",
            template: "a\u{1C}\u{1D}{{- 'b' -}}\u{1E}\u{1F}c",
            defaults: "abc",
            trimmedAndLstripped: "abc"
        ),
        Case(
            name: "empty dashed comment",
            template: "a {#-#} b",
            defaults: "a b",
            trimmedAndLstripped: "a b"
        ),
        Case(
            name: "dashed comment without a dash before the close",
            template: "a {#- c #} b",
            defaults: "a b",
            trimmedAndLstripped: "a b"
        ),
        Case(
            name: "dash inside a comment",
            template: "x{# a - b -#}  y",
            defaults: "xy",
            trimmedAndLstripped: "xy"
        ),
        Case(
            name: "dash then a negative number",
            template: "x {{-1}}",
            defaults: "x1",
            trimmedAndLstripped: "x1"
        ),
        Case(
            name: "subtraction before a dash close",
            template: "{{ 5 - 3 -}} x",
            defaults: "2x",
            trimmedAndLstripped: "2x"
        ),
        Case(
            name: "dict before a dash close",
            template: "{{ {'a': 1}['a'] -}} b",
            defaults: "1b",
            trimmedAndLstripped: "1b"
        ),
        Case(
            name: "CRLF around dashes",
            template: "a\r\n{%- if true -%}\r\nb{% endif %}",
            defaults: "ab",
            trimmedAndLstripped: "ab"
        ),
        Case(
            name: "dashed delimiters in text",
            template: "100 -%} \n ok -}} \n -#} x",
            defaults: "100 -%} \n ok -}} \n -#} x",
            trimmedAndLstripped: "100 -%} \n ok -}} \n -#} x"
        ),
        Case(
            name: "no text between tags",
            template: "{{ 'a' -}}{{- 'b' }}",
            defaults: "ab",
            trimmedAndLstripped: "ab"
        ),
        Case(
            name: "whitespace with a combining mark before",
            template: "a \u{301}{{- 'b' }}",
            defaults: "a \u{301}b",
            trimmedAndLstripped: "a \u{301}b"
        ),
    ]

    @Test(arguments: cases)
    func matchesJinja2WithDefaultOptions(_ c: Case) throws {
        let rendered = try Template(c.template).render([:])
        #expect(rendered == c.defaults)
    }

    @Test(arguments: cases)
    func matchesJinja2WithTrimAndLstripBlocks(_ c: Case) throws {
        let rendered = try Template(c.template, with: .init(lstripBlocks: true, trimBlocks: true)).render([:])
        #expect(rendered == c.trimmedAndLstripped)
    }
}
