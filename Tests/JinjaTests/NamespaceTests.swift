import Foundation
import Testing

@testable import Jinja

@Suite("Namespace Tests")
struct NamespaceTests {
    @Test(arguments: [
        ("{% set n = namespace(items=[]) %}{{ n.items }}|{{ n.items is callable }}", "[]|False"),
        ("{% set n = namespace(a=1) %}{{ n.items }}|{{ n.keys }}", "|"),
        ("{% set n = namespace(items=[1]) %}{{ n['items'] }}", "[1]"),
        ("{{ {'items': 1}.items is callable }}", "True"),
        (
            "{% set d = {'type': 'array', 'items': {'type': 'string'}} %}{{ d.items.type }}|{{ d['items'].type }}",
            "|string"
        ),
        ("{{ [{'items': 1}]|map(attribute='items')|list }}", "[1]"),
        ("{{ {'items': 1}.items()|list }}", "[['items', 1]]"),
        ("{% set n = namespace(a=1) %}{{ n }}", "<Namespace {'a': 1}>"),
        ("{% set n = namespace(a=1) %}{{ n == n }}|{{ n == namespace(a=1) }}|{{ n == {'a':1} }}", "True|False|False"),
        (
            "{% set n = namespace() %}{{ n is mapping }}|{{ n is iterable }}|{{ n is callable }}|{% if n %}True{% else %}False{% endif %}",
            "False|False|False|True"
        ),
        (
            "{% set n = namespace(items=[]) %}{% for i in [1,2] %}{% set n.items = n.items + [i] %}{% endfor %}{{ n.items }}",
            "[1, 2]"
        ),
        ("{% set n = namespace(items=[]) %}{% set n.items = n.items + [3] %}{{ n|attr('items') }}", "[3]"),
        ("{% set n = namespace(a=1) %}{{ [n] }}", "[<Namespace {'a': 1}>]"),
    ])
    func render(test: (String, String)) throws {
        #expect(try Template(test.0).render([:]) == test.1)
    }

    @Test(arguments: [
        "{% set n = namespace(items=[1]) %}{{ n.items() }}",
        "{% set n = namespace(a=1) %}{{ n.items() }}",
        "{% set n = namespace(a=1) %}{% for key in n %}{{ key }}{% endfor %}",
        "{% set n = namespace(a=1) %}{{ n|length }}",
        "{% set n = namespace(a=1) %}{{ n|tojson }}",
        "{% set n = namespace(a=1) %}{{ [n]|tojson }}",
        "{% set n = namespace(a=1) %}{{ n|list }}",
        "{% set n = namespace(a=1) %}{{ n|items|list }}",
        "{% set n = namespace(a=1) %}{{ n|random }}",
        "{% set n = namespace(a=1) %}{{ 'a' in n }}",
        "{% set n = namespace(a=1) %}{{ ','.join(n) }}",
    ])
    func rejectsMappingOperations(template: String) throws {
        #expect(throws: (any Error).self) { try Template(template).render([:]) }
    }

    @Test(arguments: [
        ("{{ rows|map(attribute='items')|list }}", "[2, 1, 2]"),
        ("{{ rows|join(',', attribute='items') }}", "2,1,2"),
        ("{{ rows|sum(attribute='items') }}", "5"),
        ("{{ rows|sort(attribute='items')|map(attribute='items')|list }}", "[1, 2, 2]"),
        ("{{ (rows|min(attribute='items'))['items'] }}", "1"),
        ("{{ (rows|max(attribute='items'))['items'] }}", "2"),
        ("{{ rows|unique(attribute='items')|map(attribute='items')|list }}", "[2, 1]"),
        ("{{ rows|groupby('items')|map(attribute='grouper')|list }}", "[1, 2]"),
        ("{{ rows|selectattr('items', 'equalto', 2)|map(attribute='items')|list }}", "[2, 2]"),
        ("{{ rows|rejectattr('items', 'equalto', 2)|map(attribute='items')|list }}", "[1]"),
    ])
    func filterLookup(test: (String, String)) throws {
        let template = "{% set rows = [{'items': 2}, {'items': 1}, {'items': 2}] %}" + test.0
        #expect(try Template(template).render([:]) == test.1)
    }

    @Test(arguments: [
        ("{% set n = namespace(a=1) %}{{ n is sequence }}|{{ n is mapping }}", "False|False"),
        ("{{ {'a': 1}|list }}", "['a']"),
        ("{% set n = namespace(a=1) %}{{ n|int }}|{{ n|int(7) }}", "0|7"),
        (
            "{% set n = namespace(a=1) %}{{ n in [1, 1.0] }}|{{ 1 in [n] }}|{{ 1.0 in [n] }}|{{ n in [1, n] }}",
            "False|False|False|True"
        ),
        (
            "{% set n = namespace(a=1) %}{{ n == 1 }}|{{ 1 == n }}|{{ n == 1.0 }}|{{ 1.0 == n }}|{{ [n, 1] == [n, 1.0] }}",
            "False|False|False|False|True"
        ),
        (
            "{% set n = namespace(a=1) %}{{ missing is sequence }}|{{ n.missing is sequence }}|{{ n.items is sequence }}",
            "True|True|True"
        ),
        (
            "{% set n = namespace(items=\"they're BILL'S\", keys='ΟΣ') %}{{ n.items.title() }}|{{ n.keys.lower() }}",
            "They'Re Bill'S|ος"
        ),
    ])
    func mergedBehavior(test: (String, String)) throws {
        #expect(try Template(test.0).render([:]) == test.1)
    }

    @Test(arguments: [
        ("{% set n = namespace() %}{{ n|urlencode }}", "%3CNamespace%20%7B%7D%3E"),
        ("{% set n = namespace(a=1) %}{{ n|urlencode }}", "%3CNamespace%20%7B%27a%27%3A%201%7D%3E"),
        (
            "{% set n = namespace(path='a/b?x=1&y=é ~') %}{{ n|urlencode }}",
            "%3CNamespace%20%7B%27path%27%3A%20%27a/b%3Fx%3D1%26y%3D%C3%A9%20~%27%7D%3E"
        ),
    ])
    func urlencode(test: (String, String)) throws {
        #expect(try Template(test.0).render([:]) == test.1)
    }

    @Test("Namespace URL quoting preserves existing string and dict behavior")
    func urlencodeOtherValues() throws {
        let environment = Environment()
        #expect(
            try Filters.urlencode([.string("<Namespace {'a': 1}>")], env: environment)
                == .string("%3CNamespace%20%7B'a':%201%7D%3E")
        )
        #expect(
            try Filters.urlencode([.object(["a": .string("x/y & z")])], env: environment)
                == .string("a=x/y%20%26%20z")
        )
    }

    @Test(arguments: [
        ("{{ namespace(items={'a': 1}.items)|dictsort|length }}", "1"),
        ("{{ namespace(items={'a': 1}.items)|xmlattr }}", " a=\"1\""),
        ("{{ namespace(items={'a': 1, 'b': 2}.items)|dictsort(reverse=true)|first|first }}", "b"),
        ("{{ namespace(items={'a': 1}.items)|xmlattr(false) }}", "a=\"1\""),
    ])
    func callableItemsFilters(test: (String, String)) throws {
        #expect(try Template(test.0).render([:]) == test.1)
    }

    @Test(arguments: [
        "{{ namespace(a=1)|dictsort }}",
        "{{ namespace(items=[1])|dictsort }}",
        "{{ namespace(a=1)|xmlattr }}",
        "{{ namespace(items=[1])|xmlattr }}",
    ])
    func rejectsNonCallableItems(template: String) throws {
        #expect(throws: (any Error).self) { try Template(template).render([:]) }
    }

    @Test("All dict method names are ordinary namespace attributes")
    func methodNames() throws {
        let namespace = try Globals.namespace(
            [],
            ["items": .int(1), "keys": .int(2), "values": .int(3), "get": .int(4)],
            Environment()
        )
        for (name, value) in [("items", 1), ("keys", 2), ("values", 3), ("get", 4)] {
            #expect(try PropertyMembers.evaluate(namespace, name) == .int(value))
            let empty = try Globals.namespace([], [:], Environment())
            #expect(try PropertyMembers.evaluate(empty, name) == .undefined)
        }
    }

    @Test("Marker names remain usable as attributes and ordinary dict keys")
    func markerName() throws {
        let key = "\0jinja.namespace"
        let namespace = try Globals.namespace([], [key: .int(42)], Environment())
        #expect(try PropertyMembers.evaluate(namespace, key) == .int(42))
        #expect(try Interpreter.evaluateComputedMember(namespace, .string(key)) == .int(42))
        #expect(try PropertyMembers.evaluate(.object([ObjectKey.string(key): .int(42)]), key) == .int(42))
        #expect(try PropertyMembers.evaluate(namespace, "items") == .undefined)
        #expect(throws: (any Error).self) { try JSONEncoder().encode(namespace) }
        let empty = try Globals.namespace([], [:], Environment())
        #expect(try PropertyMembers.evaluate(empty, key) == .undefined)
        #expect(try Interpreter.evaluateComputedMember(empty, .string(key)) == .undefined)
        #expect(
            try Filters.map([.array([empty])], kwargs: ["attribute": .string(key)], env: Environment())
                == .array([.undefined])
        )
        #expect(try Filters.pprint([empty], env: Environment()) == .string("<Namespace {}>"))
        let macro = Macro(name: "", parameters: [], defaults: [:], body: [])
        let decoded = try JSONDecoder().decode(Macro.self, from: JSONEncoder().encode(macro))
        let ordinary = Value.object([ObjectKey.string(key): .macro(decoded)])
        #expect(ordinary.namespace == nil)
        #expect(try PropertyMembers.evaluate(ordinary, "items").isFunction)
    }

    @Test("Namespace identity survives assignment without changing its hash")
    func identity() throws {
        let namespace = try Globals.namespace([], ["a": .int(1)], Environment())
        var changed = try #require(namespace.namespace)
        changed.attributes["a"] = .int(2)
        #expect(namespace == changed.value)
        #expect(namespace.isEquivalent(to: changed.value))
        #expect(Set([namespace, changed.value]).count == 1)
        #expect(namespace != (try Globals.namespace([], ["a": .int(1)], Environment())))
    }
}
