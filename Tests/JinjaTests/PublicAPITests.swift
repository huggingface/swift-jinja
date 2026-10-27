import Testing

// This file imports Jinja without `@testable`,
// so it compiles only against the public rendering API.
import Jinja

/// Renders templates through the public API:
/// `Template`, `Value`, `Environment`, and the filter, test, and global extension points.
/// Expected strings were rendered with jinja2 3.1.6.
@Suite("Public API")
struct PublicAPITests {
    @Test("Render a template with context values")
    func renderContext() throws {
        let template = try Template("Hello, {{ name }}!")
        #expect(try template.render(["name": "World"]) == "Hello, World!")
    }

    @Test("Render a template with options")
    func renderWithOptions() throws {
        let template = try Template(
            "{% for item in items %}\n    {{ item }}\n{% endfor %}\n",
            with: Template.Options(lstripBlocks: true, trimBlocks: true)
        )
        #expect(try template.render(["items": ["a", "b"]]) == "    a\n    b\n")
    }

    @Test("Call a global function from the environment")
    func globalFunction() throws {
        let environment = Environment()
        environment["shout"] = .function { args, _, _ in
            guard case let .string(string) = args.first else { return .undefined }
            return .string(string.uppercased() + "!")
        }
        let template = try Template("{{ shout('hi') }}")
        #expect(try template.render([:], environment: environment) == "HI!")
    }

    @Test("Apply a custom filter from the environment")
    func customFilter() throws {
        let environment = Environment()
        environment["double"] = .function { args, _, _ in
            guard case let .int(int) = args.first else { return .undefined }
            return .int(int * 2)
        }
        let template = try Template("{{ 21 | double }}")
        #expect(try template.render([:], environment: environment) == "42")
    }

    @Test("Wrap a built-in filter")
    func builtInFilterWrapper() throws {
        let environment = Environment()
        environment["loud"] = .function { args, kwargs, env in
            try Filters.upper(args, kwargs: kwargs, env: env)
        }
        let template = try Template("{{ 'hi' | loud }}")
        #expect(try template.render([:], environment: environment) == "HI")
    }

    @Test("Apply a custom test from the environment")
    func customTest() throws {
        let environment = Environment()
        environment["positive"] = .function { args, _, _ in
            guard case let .int(int) = args.first else { return false }
            return .boolean(int > 0)
        }
        let template = try Template("{{ 3 is positive }} {{ -3 is positive }}")
        #expect(try template.render([:], environment: environment) == "True False")
    }

    @Test("Call a macro defined in the template")
    func macro() throws {
        let template = try Template(
            "{% macro greet(name='World') %}Hello, {{ name }}!{% endmacro %}{{ greet() }} {{ greet('Alice') }}"
        )
        #expect(try template.render([:]) == "Hello, World! Hello, Alice!")
    }

    @Test("Read the name and parameters of a macro value")
    func macroValue() throws {
        let environment = Environment()
        environment["describe"] = .function { args, _, _ in
            guard case let .macro(macro) = args.first else { return .undefined }
            return .string("\(macro.name)(\(macro.parameters.joined(separator: ", ")))")
        }
        let template = try Template(
            "{% macro greet(name, punctuation='!') %}{% endmacro %}{{ describe(greet) }}"
        )
        #expect(try template.render([:], environment: environment) == "greet(name, punctuation)")
    }

    @Test("Limit nested macro calls")
    func maximumCallDepth() throws {
        let environment = Environment()
        environment.maximumCallDepth = 2
        let source = "{% macro r(n) %}{% if n > 0 %}{{ r(n - 1) }}{% endif %}{{ n }}{% endmacro %}"
        #expect(try Template(source + "{{ r(1) }}").render([:], environment: environment) == "01")
        #expect(throws: JinjaError.self) {
            try Template(source + "{{ r(2) }}").render([:], environment: environment)
        }
    }

    @Test("Serialize JSON with the Jinja2 policies")
    func jinja2Policies() throws {
        let environment = Environment()
        environment.policies = .jinja2
        let template = try Template("{{ tool | tojson }}")
        let tool: Value = ["name": "café", "args": "<x>"]
        #expect(
            try template.render(["tool": tool], environment: environment)
                == #"{"args": "\u003cx\u003e", "name": "caf\u00e9"}"#
        )
    }

    @Test("Throw a JinjaError for a syntax error")
    func syntaxError() {
        #expect(throws: JinjaError.self) {
            try Template("{% if %}")
        }
    }
}
