import Foundation
import Testing

@testable import Jinja

/// Macro recursion that doesn't end throws instead of overflowing the stack.
/// Jinja2 3.1.6 raises `RecursionError` for each of these templates.
@Suite("Macro recursion")
struct MacroRecursionTests {
    /// Renders a template on a new thread with the given stack size.
    ///
    /// Threads other than the main thread get a 512 KB stack by default on Apple platforms.
    func render(
        _ source: String,
        _ context: [String: Value] = [:],
        stackSize: Int = 512 * 1024
    ) async throws -> String {
        let template = try Template(source)
        let result: Result<String, any Error> = await withCheckedContinuation { continuation in
            let thread = Thread {
                continuation.resume(returning: Result { try template.render(context) })
            }
            thread.stackSize = stackSize
            thread.start()
        }
        return try result.get()
    }

    @Test(
        "Unbounded recursion throws on a 512 KB stack",
        arguments: [
            "{% macro r() %}{{ r() }}{% endmacro %}{{ r() }}",
            "{% macro r(n) %}{% if n > 0 %}{{ r(n - 1) }}{% endif %}{% endmacro %}{{ r(1000) }}",
            "{% macro a() %}{{ b() }}{% endmacro %}{% macro b() %}{{ a() }}{% endmacro %}{{ a() }}",
            """
            {% macro m() %}{{ caller() }}{% endmacro %}\
            {% macro r() %}{% call m() %}{{ r() }}{% endcall %}{% endmacro %}{{ r() }}
            """,
        ]
    )
    func unboundedRecursionThrows(source: String) async throws {
        do {
            let rendered = try await render(source)
            Issue.record("Expected a runtime error; rendered \(rendered)")
        } catch JinjaError.runtime(let message) {
            #expect(message == "Maximum recursion depth of 20 exceeded")
        }
    }

    @Test("Recursion within the limit renders")
    func recursionWithinLimitRenders() async throws {
        // Twenty nested calls, from r(19) to r(0).
        let source = "{% macro r(n) %}{% if n > 0 %}{{ r(n - 1) }}{% endif %}{{ n }}{% endmacro %}{{ r(19) }}"
        #expect(try await render(source) == "012345678910111213141516171819")
    }

    @Test("Recursion past the limit throws")
    func recursionPastLimitThrows() async throws {
        // Jinja2 renders this template, which makes 21 nested calls.
        let source = "{% macro r(n) %}{% if n > 0 %}{{ r(n - 1) }}{% endif %}{{ n }}{% endmacro %}{{ r(20) }}"
        await #expect(throws: JinjaError.self) {
            try await render(source)
        }
    }

    /// The type macro of the Hermes 3 tool-use template.
    static let jsonToPythonType = """
        {%- macro json_to_python_type(json_spec) %}
        {%- set basic_type_map = {"string": "str", "number": "float", "integer": "int", "boolean": "bool"} %}
        {%- if basic_type_map[json_spec.type] is defined %}
            {{- basic_type_map[json_spec.type] }}
        {%- elif json_spec.type == "array" %}
            {{- "list[" +  json_to_python_type(json_spec|items) + "]"}}
        {%- elif json_spec.type == "object" %}
            {{- "dict" }}
        {%- elif json_spec.type is iterable %}
            {{- "Union[" }}
            {%- for t in json_spec.type %}
                {{- json_to_python_type({"type": t}) }}
                {%- if not loop.last %}{{- "," }}{%- endif %}
            {%- endfor %}
            {{- "]" }}
        {%- else %}
            {{- "Any" }}
        {%- endif %}
        {%- endmacro %}
        {{- json_to_python_type(spec) }}
        """

    @Test("A JSON schema type with alternatives renders")
    func jsonSchemaTypeWithAlternativesRenders() async throws {
        let spec: Value = ["type": ["string", "integer"]]
        #expect(try await render(Self.jsonToPythonType, ["spec": spec]) == "Union[str,int]")
    }

    @Test("A JSON schema type with a null alternative throws")
    func jsonSchemaTypeWithNullAlternativeThrows() async throws {
        // For a type of `["string", "null"]`, the macro iterates over the characters of "null"
        // and recurses on each one without end.
        // Each call takes more stack in a debug build than a 512 KB stack can hold for 20 calls,
        // so this test uses the 8 MB stack of a main thread.
        let spec: Value = ["type": ["string", "null"]]
        do {
            let rendered = try await render(Self.jsonToPythonType, ["spec": spec], stackSize: 8 * 1024 * 1024)
            Issue.record("Expected a runtime error; rendered \(rendered)")
        } catch JinjaError.runtime(let message) {
            #expect(message == "Maximum recursion depth of 20 exceeded")
        }
    }
}
