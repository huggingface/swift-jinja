import Testing

@testable import Jinja

/// Rendering with an environment that the caller passes.
/// Expected values are from Jinja2 3.1.6,
/// with `env.globals` in the place of the environment's variables.
@Suite("Render Environment Tests")
struct RenderEnvironmentTests {
    @Test("Context values don't carry over to later renders")
    func contextDoesNotCarryOver() throws {
        let env = Environment()
        #expect(try Template("{{ x }}").render(["x": 1], environment: env) == "1")
        #expect(try Template("[{{ x }}]").render([:], environment: env) == "[]")
        #expect(env["x"] == .undefined)
    }

    @Test("Variables and macros that a template sets don't carry over")
    func setAndMacroDoNotCarryOver() throws {
        let env = Environment()
        #expect(try Template("{% set y = 2 %}{{ y }}").render([:], environment: env) == "2")
        #expect(try Template("[{{ y }}]").render([:], environment: env) == "[]")
        #expect(try Template("{% macro m() %}M{% endmacro %}{{ m() }}").render([:], environment: env) == "M")
        #expect(try Template("[{{ m is defined }}]").render([:], environment: env) == "[False]")
    }

    @Test("Environment variables are visible to the template")
    func environmentVariablesVisible() throws {
        let env = Environment()
        env["site"] = "example"
        #expect(try Template("{{ site }}").render([:], environment: env) == "example")
    }

    @Test("A context value hides an environment variable for one render")
    func contextHidesEnvironmentVariable() throws {
        let env = Environment()
        env["greeting"] = "hi"
        let template = try Template("{{ greeting }}")
        #expect(try template.render(["greeting": "hello"], environment: env) == "hello")
        #expect(try template.render([:], environment: env) == "hi")
    }

    @Test("A context value hides a built-in global")
    func contextHidesBuiltIn() throws {
        #expect(try Template("{{ range }}").render(["range": "r"]) == "r")
        #expect(try Template("{{ namespace }}").render(["namespace": "n"]) == "n")
    }

    @Test("An environment variable hides a built-in global")
    func environmentVariableHidesBuiltIn() throws {
        let env = Environment()
        env["range"] = "r"
        #expect(try Template("{{ range }}").render([:], environment: env) == "r")
    }

    @Test("A template set hides an environment variable for one render")
    func setHidesEnvironmentVariable() throws {
        let env = Environment()
        env["g"] = "global"
        #expect(try Template("{% set g = 'local' %}{{ g }}").render([:], environment: env) == "local")
        #expect(try Template("{{ g }}").render([:], environment: env) == "global")
        #expect(env["g"] == "global")
    }

    @Test("Variables of parent environments are visible to the template")
    func parentEnvironmentVariablesVisible() throws {
        let parent = Environment()
        parent["a"] = "env"
        parent["b"] = "env"
        let child = Environment(parent: parent)
        child["b"] = "template"
        #expect(try Template("{{ a }} {{ b }}").render([:], environment: child) == "env template")
    }

    @Test("A namespace that a template creates starts over for each render")
    func namespaceInTemplate() throws {
        let env = Environment()
        let template = try Template(
            "{% set ns = namespace(n=0) %}{% for i in [1, 2, 3] %}{% set ns.n = ns.n + i %}{% endfor %}{{ ns.n }}"
        )
        #expect(try template.render([:], environment: env) == "6")
        #expect(try template.render([:], environment: env) == "6")
        #expect(try Template("[{{ ns is defined }}]").render([:], environment: env) == "[False]")
    }

    @Test("Assigning an attribute of an environment variable doesn't change the environment")
    func namespaceInEnvironment() throws {
        // Jinja2 renders "1", "2", "3" for a `Namespace` object in `env.globals`,
        // because the template changes that shared object.
        // A namespace here is a value, so each render changes its own copy.
        let env = Environment()
        env["ns"] = try Globals.namespace([], ["n": 0], env)
        let template = try Template("{% set ns.n = ns.n + 1 %}{{ ns.n }}")
        for _ in 0 ..< 3 {
            #expect(try template.render([:], environment: env) == "1")
        }
        #expect(env["ns"] == ["n": 0])
    }

    @Test("A cycler in the environment shares its position across renders")
    func cyclerInEnvironment() throws {
        let env = Environment()
        env["c"] = try Globals.cycler(["a", "b", "c"], [:], env)
        let template = try Template("{{ c.next() }}")
        let outputs = try (0 ..< 4).map { _ in try template.render([:], environment: env) }
        #expect(outputs == ["a", "b", "c", "a"])
    }

    @Test("A cycler and a joiner that a template creates start over for each render")
    func cyclerAndJoinerInTemplate() throws {
        let env = Environment()
        let template = try Template(
            "{% set c = cycler('a', 'b') %}{% set j = joiner('-') %}{% for i in [1, 2, 3] %}{{ j() }}{{ c.next() }}{% endfor %}"
        )
        #expect(try template.render([:], environment: env) == "a-b-a")
        #expect(try template.render([:], environment: env) == "a-b-a")
    }

    @Test("Rendering with one environment from many tasks gives the right results")
    func concurrentRenders() async throws {
        let env = Environment()
        env.policies = .jinja2
        env["greeting"] = "Hello"
        let template = try Template(
            "{% set ns = namespace(total=0) %}"
                + "{% for i in items %}{% set ns.total = ns.total + i %}{% endfor %}"
                + "{% macro tag(v) %}<{{ v }}>{% endmacro %}"
                + "{{ greeting }} {{ name }}: {{ tag(ns.total) }} {{ data | tojson }}"
        )

        func context(_ n: Int) -> Context {
            [
                "name": .string("user\(n)"),
                "items": .array((0 ..< n % 10).map { .int($0) }),
                "data": ["b": .int(n), "a": "é"],
            ]
        }

        // Jinja2 renders `Hello user7: <21> {"a": "\u00e9", "b": 7}` for n = 7.
        func expected(_ n: Int) -> String {
            let total = (0 ..< n % 10).reduce(0, +)
            return #"Hello user\#(n): <\#(total)> {"a": "\u00e9", "b": \#(n)}"#
        }

        let count = 1000
        let results = try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for n in 0 ..< count {
                group.addTask {
                    (n, try template.render(context(n), environment: env))
                }
            }
            var results: [Int: String] = [:]
            for try await (n, output) in group {
                results[n] = output
            }
            return results
        }

        #expect(results.count == count)
        for n in 0 ..< count {
            #expect(results[n] == expected(n))
        }
        for name in ["name", "items", "data", "ns", "tag"] {
            #expect(env[name] == .undefined)
        }
    }
}
