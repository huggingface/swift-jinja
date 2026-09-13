import Testing

@testable import Jinja

/// Whitespace control on comment tags: `{#-` strips whitespace before the comment and `-#}`
/// strips it after, as `{%-`/`-%}` and `{{-`/`-}}` already do. Expected strings were rendered
/// with Python jinja2 3.1.6, the reference implementation transformers renders chat templates with.
///
/// Real chat templates depend on it: Llama 3.1's template has 5 `{#-` comments and gpt-oss's has 25.
/// Without it, each leaves its preceding newlines in the prompt, so the model is fed tokens the
/// Python tokenizer never produces.
@Suite("Comment whitespace control")
struct CommentWhitespaceControlTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let template: String
        /// jinja2 with trim_blocks=True, lstrip_blocks=True (how chat templates are rendered).
        let trimmedAndLstripped: String
        /// jinja2 with default options.
        let defaults: String
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(
            name: "dash opening a comment",
            template: "a\n\n{#- note #}\nb",
            trimmedAndLstripped: "ab",
            defaults: "a\nb"
        ),
        Case(
            name: "dash closing a comment",
            template: "a\n{# note -#}\n\n  b",
            trimmedAndLstripped: "a\nb",
            defaults: "a\nb"
        ),
        Case(
            name: "dashes on both sides",
            template: "a  \n{#- note -#}\n  b",
            trimmedAndLstripped: "ab",
            defaults: "ab"
        ),
        Case(
            name: "plain comment is unchanged",
            template: "a\n{# note #}\nb",
            trimmedAndLstripped: "a\nb",
            defaults: "a\n\nb"
        ),
        Case(
            name: "multi-line dashed comment between statements",
            template: "x{%- if true %}\n{%- endif %}\n\n{#-\n  long\n  note\n#}\n{%- if true %}y{%- endif %}",
            trimmedAndLstripped: "xy",
            defaults: "xy"
        ),
        Case(
            name: "literal brace before a dashed comment",
            template: "{\n{#- note #}z",
            trimmedAndLstripped: "{z",
            defaults: "{z"
        ),
        // A dashed comment after a plain one must not swallow the text between them.
        Case(
            name: "text between a plain and a dashed comment survives",
            template: "{# a #} keep {# b -#}\n z",
            trimmedAndLstripped: " keep z",
            defaults: " keep z"
        ),
    ]

    @Test(arguments: cases)
    func matchesJinja2WithTrimAndLstripBlocks(_ c: Case) throws {
        let rendered = try Template(c.template, with: .init(lstripBlocks: true, trimBlocks: true)).render([:])
        #expect(rendered == c.trimmedAndLstripped)
    }

    @Test(arguments: cases)
    func matchesJinja2WithDefaultOptions(_ c: Case) throws {
        let rendered = try Template(c.template).render([:])
        #expect(rendered == c.defaults)
    }
}
