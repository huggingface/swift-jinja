import Testing

@testable import Jinja

@Suite("Numeric attribute access")
struct NumericAttributeTests {
    @Test func numericAttributesDoNotConsumeTheNextDot() throws {
        let tokens = try Lexer.tokenize("{{ values.0.1.name }}")
        #expect(tokens.map(\.kind) == [
            .openExpression, .identifier, .dot, .number, .dot, .number,
            .dot, .identifier, .closeExpression, .eof,
        ])
        #expect(tokens.filter { $0.kind == .number }.map { String($0.value) } == ["0", "1"])
        #expect(try Parser.parse(Lexer.tokenize("{{ values.0.name }}")) == [
            .expression(.member(
                .member(.identifier("values"), .integer(0), computed: true),
                .identifier("name"), computed: false)),
        ])
    }

    @Test func nestedNumericAndNamedAttributesMatchBracketAccess() throws {
        let context: Context = [
            "values": .array([.array([.object(["name": .string("first")]),
                                     .object(["name": .string("second")])])]),
            "word": .string("word"),
            "mapping": .object(["0": .string("string key")]),
        ]
        let template = try Template(
            "{{ values.0.1.name }}|{{ values[0][1].name }}|{{ word.1 }}|"
                + "{{ values.99 is undefined }}|{{ mapping.0 is undefined }}|{{ mapping['0'] }}")
        #expect(try template.render(context) == "second|second|o|true|true|string key")
        #expect(try Template("{{ values.00.1.name }}").render(context) == "second")
    }

    @Test func ordinaryDecimalsAndAttributeNamesAreUnchanged() throws {
        #expect(try Template("{{ 1.25 + 2.5 }}").render([:]) == "3.75")
        #expect(try Template("{{ object.name }}").render([
            "object": .object(["name": .string("kept")])
        ]) == "kept")
    }

    @Test func invalidNumericAttributesNeverBecomeIndexZero() {
        for source in [
            "{{ values.01 }}", "{{ values.-1 }}", "{{ values.1e2 }}",
            "{{ values.0foo }}", "{{ values.18446744073709551616 }}", "{{ values.١ }}",
            "{{ values.0_foo }}", "{{ values.0é }}", "{{ values.0 foo }}",
            "{{ values.0\tfoo }}", "{{ values.0\nfoo }}", "{{ values.0 1 }}",
            "{{ values.0 'suffix' }}", "{{ values.0true }}", "{{ values.0{} }}",
        ] {
            #expect(throws: JinjaError.self) { try Template(source) }
        }
    }

    @Test func numericAttributeBoundariesKeepPostfixAndKeywordOperators() throws {
        let context: Context = [
            "values": .array([.array([.string("A"), .string("B")])]),
            "cond": .boolean(true),
            "handlers": .array([.function { _, _, _ in .string("called") }]),
        ]
        for source in ["{{ values.0.1 }}", "{{ values . 0 . 1 }}", "{{ values.0[1] }}"] {
            #expect(try Template(source).render(context) == "B")
        }
        #expect(try Template("{{ values.0|length }}").render(context) == "2")
        #expect(try Template("{{ values.0is defined }}").render(context) == "true")
        #expect(try Template("{{ values.0and 'yes' }}").render(context) == "yes")
        #expect(try Template("{{ (values.0if cond else [])|length }}").render(context) == "2")
        #expect(try Template("{{ 'yes' if values.0 else 'no' }}").render(context) == "yes")
        #expect(try Template("{{ handlers.0() }}").render(context) == "called")
    }

    @Test func numericAttributeValidationDoesNotChangeLiteralConcatenation() throws {
        #expect(try Template("{{ 'values.1e2' ' values.0foo' }}").render([:])
            == "values.1e2 values.0foo")
        #expect(try Template("{{ 1.25 + 2.5 }}").render([:]) == "3.75")
    }

    @Test func numericAccessWorksInsideNestedMacrosNamespacesAndBreaks() throws {
        let source = """
            {%- macro emit(message) -%}
              {%- if message.content.0.type == 'tool_reference' -%}
                {{- message.content.0.output -}}
              {%- endif -%}
            {%- endmacro -%}
            {%- set state = namespace(count=0) -%}
            {%- for group in groups -%}
              {%- for message in group -%}
                {%- if message.content.0.type == 'tool_reference' -%}
                  {%- set state.count = state.count + 1 -%}
                  {{- emit(message) -}}
                  {%- break -%}
                {%- endif -%}
              {%- endfor -%}
            {%- endfor -%}
            |{{ state.count }}
            """
        func message(_ type: String, _ output: String) -> Value {
            .object(["content": .array([.object([
                "type": .string(type), "output": .string(output),
            ])])])
        }
        let context: Context = ["groups": .array([
            .array([message("text", "ignored"), message("tool_reference", "A")]),
            .array([message("tool_reference", "B"), message("tool_reference", "ignored")]),
        ])]
        #expect(try Template(source).render(context) == "AB|2")
    }
}
