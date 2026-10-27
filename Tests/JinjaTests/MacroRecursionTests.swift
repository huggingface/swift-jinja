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
        environment: Environment? = nil,
        stackSize: Int = 512 * 1024
    ) async throws -> String {
        let template = try Template(source)
        let result: Result<String, any Error> = await withCheckedContinuation { continuation in
            let thread = Thread {
                continuation.resume(returning: Result { try template.render(context, environment: environment) })
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
            #expect(message == "Maximum recursion depth of 16 exceeded")
        }
    }

    @Test("Recursion within the limit renders")
    func recursionWithinLimitRenders() async throws {
        // Sixteen nested calls, from r(15) to r(0).
        let source = "{% macro r(n) %}{% if n > 0 %}{{ r(n - 1) }}{% endif %}{{ n }}{% endmacro %}{{ r(15) }}"
        #expect(try await render(source) == "0123456789101112131415")
    }

    @Test("Recursion past the limit throws")
    func recursionPastLimitThrows() async throws {
        // Jinja2 renders this template, which makes 17 nested calls.
        let source = "{% macro r(n) %}{% if n > 0 %}{{ r(n - 1) }}{% endif %}{{ n }}{% endmacro %}{{ r(16) }}"
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
        // Each call takes more stack in a debug build than a 512 KB stack can hold for 16 calls,
        // so this test uses the 8 MB stack of a main thread.
        let spec: Value = ["type": ["string", "null"]]
        do {
            let rendered = try await render(Self.jsonToPythonType, ["spec": spec], stackSize: 8 * 1024 * 1024)
            Issue.record("Expected a runtime error; rendered \(rendered)")
        } catch JinjaError.runtime(let message) {
            #expect(message == "Maximum recursion depth of 16 exceeded")
        }
    }

    /// Renders `source` and expects it to exceed a call depth limit of `limit`.
    func expectLimitExceeded(
        _ source: String,
        limit: Int,
        environment: Environment? = nil,
        stackSize: Int = 512 * 1024
    ) async throws {
        do {
            let rendered = try await render(source, environment: environment, stackSize: stackSize)
            Issue.record("Expected a runtime error; rendered \(rendered)")
        } catch JinjaError.runtime(let message) {
            #expect(message == "Maximum recursion depth of \(limit) exceeded")
        }
    }

    /// Makes `n + 1` nested calls, from `r(n)` to `r(0)`, and prints each `n`.
    static func countdown(_ n: Int) -> String {
        "{% macro r(n) %}{% if n > 0 %}{{ r(n - 1) }}{% endif %}{{ n }}{% endmacro %}{{ r(\(n)) }}"
    }

    @Test("The default limit is 16 calls")
    func defaultLimit() async throws {
        #expect(Environment().maximumCallDepth == 16)
        try await expectLimitExceeded(Self.countdown(16), limit: 16, environment: Environment())
    }

    @Test("A raised limit renders recursion that the default limit rejects")
    func raisedLimit() async throws {
        let environment = Environment()
        environment.maximumCallDepth = 32
        // A raised limit needs a larger stack than the 512 KB of a secondary thread,
        // so this test uses the 8 MB stack of a main thread.
        let stackSize = 8 * 1024 * 1024
        let rendered = try await render(Self.countdown(16), environment: environment, stackSize: stackSize)
        #expect(rendered == "012345678910111213141516")
        try await expectLimitExceeded(Self.countdown(32), limit: 32, environment: environment, stackSize: stackSize)
    }

    @Test("A lowered limit throws earlier")
    func loweredLimit() async throws {
        let environment = Environment()
        environment.maximumCallDepth = 4
        #expect(try await render(Self.countdown(3), environment: environment) == "0123")
        try await expectLimitExceeded(Self.countdown(4), limit: 4, environment: environment)
    }

    @Test("The limit counts caller invocations")
    func limitCountsCaller() async throws {
        // Calling m and then caller makes two nested calls.
        let source = "{% macro m() %}{{ caller() }}{% endmacro %}{% call m() %}x{% endcall %}"
        let environment = Environment()
        environment.maximumCallDepth = 1
        try await expectLimitExceeded(source, limit: 1, environment: environment)
        environment.maximumCallDepth = 2
        #expect(try await render(source, environment: environment) == "x")
    }

    @Test("A child environment inherits the limit of its parent")
    func childInheritsLimit() async throws {
        let parent = Environment()
        parent.maximumCallDepth = 4
        let child = Environment(parent: parent)
        #expect(child.maximumCallDepth == 4)
        try await expectLimitExceeded(Self.countdown(4), limit: 4, environment: child)

        child.maximumCallDepth = 8
        #expect(child.maximumCallDepth == 8)
        #expect(parent.maximumCallDepth == 4)
    }

    @Test("A limit less than 1 is stored as 1", arguments: [0, -1, Int.min])
    func limitBelowOne(limit: Int) {
        let environment = Environment()
        environment.maximumCallDepth = limit
        #expect(environment.maximumCallDepth == 1)
    }
}
