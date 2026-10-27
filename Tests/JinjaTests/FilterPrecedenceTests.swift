import Testing

@testable import Jinja

/// As in Jinja2, filters (`|`) and tests (`is`) bind tighter than the binary operators,
/// and only adjacent string literals concatenate implicitly.
/// Expected strings were rendered with jinja2 3.1.6.
@Suite("Filter precedence")
struct FilterPrecedenceTests {
    static let context: Context = [
        "x": "abc",
        "a": "x",
        "b": "y",
        "n": 5,
        "items": [1, 2, 3],
        "y": true,
    ]

    @Test(
        "Filters bind tighter than binary operators",
        arguments: [
            ("{{ x|length * 2 }}", "6"),
            ("{{ x|length / 2 }}", "1.5"),
            ("{{ x|length // 2 }}", "1"),
            ("{{ x|length % 2 }}", "1"),
            ("{{ x|length ** 2 }}", "9"),
            ("{{ 2 * 3|string }}", "33"),
            ("{{ 2 ** x|length }}", "8"),
            ("{{ 10 // items|length }}", "3"),
            ("{{ items|length * 2 + 1 }}", "7"),
            ("{{ items|length - 1 }}", "2"),
            ("{{ x|upper ~ 'd' }}", "ABCd"),
            ("{{ 'ab' * 2|int }}", "abab"),
            ("{{ x|attr('upper')() }}", "ABC"),
        ]
    )
    func filters(template: String, expected: String) throws {
        #expect(try Template(template).render(Self.context) == expected)
    }

    @Test(
        "Filters apply to the result of unary operators",
        arguments: [
            ("{{ -1|abs }}", "1"),
            ("{{ -3.7|round }}", "-4.0"),
            ("{{ -n|string }}", "-5"),
            ("{{ - - n|string }}", "5"),
            ("{{ +n|string }}", "5"),
            ("{{ -2 ** 2 }}", "4"),
            ("{{ -n is odd }}", "True"),
            ("{{ not x|length }}", "False"),
            ("{{ not n is odd }}", "False"),
            ("{{ not n is even }}", "True"),
        ]
    )
    func unaryOperators(template: String, expected: String) throws {
        #expect(try Template(template).render(Self.context) == expected)
    }

    @Test(
        "Tests bind tighter than binary operators",
        arguments: [
            ("{{ x ~ 'd' is string }}", "abcTrue"),
            ("{{ a ~ b is defined }}", "xTrue"),
            ("{{ a is in x ~ '!' }}", "False!"),
            ("{{ n is odd and y }}", "True"),
            ("{{ n is even or y }}", "True"),
            ("{{ 'yes' if n is odd else 'no' }}", "yes"),
            ("{{ n is not none }}", "True"),
            ("{{ n is not odd }}", "False"),
            ("{{ n is divisibleby(5)|string }}", "True"),
            ("{{ n is odd|string }}", "True"),
            ("{{ n is not odd|string }}", "False"),
            ("{{ x|length is odd }}", "True"),
            ("{{ n is sameas 5 }}", "True"),
            ("{{ n is in [5, 6] }}", "True"),
            ("{{ n is not in [1, 2] }}", "True"),
            ("{{ n is in items }}", "False"),
            ("{{ 'k' is in {'k': 1} }}", "True"),
            ("{{ n is eq (5) }}", "True"),
            ("{{ n is eq n }}", "True"),
            ("{% for i in items if i is odd %}{{ i }}{% endfor %}", "13"),
            ("{% if n is odd and n > 2 %}yes{% endif %}", "yes"),
            ("{% if n is not none and n|string == '5' %}yes{% endif %}", "yes"),
            ("{% if false %}{{ n is even in [] }}{% endif %}", ""),
        ]
    )
    func tests(template: String, expected: String) throws {
        #expect(try Template(template).render(Self.context) == expected)
    }

    @Test(
        "An empty subscript is a subscript by the empty tuple",
        arguments: [
            ("{{ items[] }}", ""),
            ("{{ items[] is defined }}", "False"),
            ("{{ x[]|default('none') }}", "none"),
        ]
    )
    func emptySubscript(template: String, expected: String) throws {
        #expect(try Template(template).render(Self.context) == expected)
    }

    @Test(
        "Adjacent string literals concatenate",
        arguments: [
            ("{{ 'a' 'b' }}", "ab"),
            (#"{{ 'a' "b" 'c' }}"#, "abc"),
            ("{{ 'a' 'b'|upper }}", "AB"),
            ("{{ 'a' + 'b' 'c' }}", "abc"),
            ("{% set s = 'a' 'b' %}{{ s }}", "ab"),
            ("{{ 'a' ['b'] }}", ""),
        ]
    )
    func stringLiterals(template: String, expected: String) throws {
        #expect(try Template(template).render(Self.context) == expected)
    }

    // Jinja2 raises a TemplateSyntaxError for each of these.
    @Test(
        "Invalid syntax",
        arguments: [
            "{{ a b }}",
            "{{ 'a' a }}",
            "{{ a 'b' }}",
            "{{ 1 2 }}",
            "{{ 'a' 1 }}",
            "{{ true 'a' }}",
            "{{ none 'a' }}",
            "{{ n is odd if y else 'no' }}",
            "{{ n is defined in items }}",
            "{{ n is defined is defined }}",
        ]
    )
    func invalidSyntax(template: String) {
        #expect(throws: JinjaError.self) {
            try Template(template)
        }
    }

    // Jinja2 raises an error when it renders each of these.
    @Test(
        "Runtime errors",
        arguments: [
            "{{ -items|length }}",
            "{{ n is divisibleby -1 }}",
            "{{ 'a' ('b') }}",
        ]
    )
    func runtimeErrors(template: String) {
        #expect(throws: (any Error).self) {
            try Template(template).render(Self.context)
        }
    }

    @Test("Filters and tests parse inside binary operators")
    func syntaxTree() throws {
        let nodes = try Parser.parse(Lexer.tokenize("{{ 2 * x|length is odd }}"))
        #expect(
            nodes == [
                .expression(
                    .binary(
                        .multiply,
                        .integer(2),
                        .test(.filter(.identifier("x"), "length", [], [:]), "odd", [], negated: false)
                    )
                )
            ]
        )
    }
}
