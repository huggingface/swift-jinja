import Testing

@testable import Jinja

/// `{#-` strips the whitespace before a comment and `-#}` the whitespace after it,
/// as the dashes already do for statements and expressions.
/// Expected strings were rendered with jinja2 3.1.6.
@Suite("Comment whitespace control")
struct CommentWhitespaceControlTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let template: String
        let defaults: String
        let trimmedAndLstripped: String
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(
            name: "dash opening a comment",
            template: "a\n\n{#- note #}\nb",
            defaults: "a\nb",
            trimmedAndLstripped: "ab"
        ),
        Case(
            name: "dash closing a comment",
            template: "a\n{# note -#}\n\n  b",
            defaults: "a\nb",
            trimmedAndLstripped: "a\nb"
        ),
        Case(
            name: "dashes on both sides",
            template: "a  \n{#- note -#}\n  b",
            defaults: "ab",
            trimmedAndLstripped: "ab"
        ),
        Case(
            name: "plain comment is unchanged",
            template: "a\n{# note #}\nb",
            defaults: "a\n\nb",
            trimmedAndLstripped: "a\nb"
        ),
        Case(
            name: "multi-line dashed comment between statements",
            template: "x{%- if true %}\n{%- endif %}\n\n{#-\n  long\n  note\n#}\n{%- if true %}y{%- endif %}",
            defaults: "xy",
            trimmedAndLstripped: "xy"
        ),
        Case(
            name: "text between a plain and a dashed comment survives",
            template: "{# a #} keep {# b -#}\n z",
            defaults: " keep z",
            trimmedAndLstripped: " keep z"
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
