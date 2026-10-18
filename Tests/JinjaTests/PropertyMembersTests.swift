import Foundation
import Testing

@testable import Jinja

@Suite("Property Members Tests")
struct PropertyMembersTests {

    // MARK: - String Property Tests

    @Test("String upper method")
    func stringUpper() throws {
        let value = Value.string("hello world")
        let result = try PropertyMembers.evaluate(value, "upper")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let upperResult = try fn([], [:], Environment())
        #expect(upperResult == .string("HELLO WORLD"))
    }

    @Test("String lower method")
    func stringLower() throws {
        let value = Value.string("HELLO WORLD")
        let result = try PropertyMembers.evaluate(value, "lower")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let lowerResult = try fn([], [:], Environment())
        #expect(lowerResult == .string("hello world"))
    }

    @Test("String title method")
    func stringTitle() throws {
        let value = Value.string("hello world")
        let result = try PropertyMembers.evaluate(value, "title")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let titleResult = try fn([], [:], Environment())
        #expect(titleResult == .string("Hello World"))
    }

    @Test("String strip method")
    func stringStrip() throws {
        let value = Value.string("  hello world  ")
        let result = try PropertyMembers.evaluate(value, "strip")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let stripResult = try fn([], [:], Environment())
        #expect(stripResult == .string("hello world"))
    }

    @Test("String strip with chars")
    func stringStripWithChars() throws {
        let value = Value.string("xy</answer>")
        let result = try PropertyMembers.evaluate(value, "strip")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let stripResult = try fn([.string("</answer>")], [:], Environment())
        #expect(stripResult == .string("xy"))
    }

    @Test("String lstrip method")
    func stringLstrip() throws {
        let value = Value.string("  hello world  ")
        let result = try PropertyMembers.evaluate(value, "lstrip")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let lstripResult = try fn([], [:], Environment())
        #expect(lstripResult == .string("hello world  "))
    }

    @Test("String lstrip with chars")
    func stringLstripWithChars() throws {
        let value = Value.string("///path")
        let result = try PropertyMembers.evaluate(value, "lstrip")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let lstripResult = try fn([.string("/")], [:], Environment())
        #expect(lstripResult == .string("path"))
    }

    @Test("String rstrip method")
    func stringRstrip() throws {
        let value = Value.string("  hello world  ")
        let result = try PropertyMembers.evaluate(value, "rstrip")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let rstripResult = try fn([], [:], Environment())
        #expect(rstripResult == .string("  hello world"))
    }

    @Test("String rstrip with chars")
    func stringRstripWithChars() throws {
        let value = Value.string("hello...")
        let result = try PropertyMembers.evaluate(value, "rstrip")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let rstripResult = try fn([.string(".")], [:], Environment())
        #expect(rstripResult == .string("hello"))
    }

    @Test("String strip with non-string chars throws")
    func stringStripNonStringChars() throws {
        let value = Value.string("  hello  ")
        let result = try PropertyMembers.evaluate(value, "strip")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        #expect(throws: JinjaError.self) {
            _ = try fn([.int(42)], [:], Environment())
        }
    }

    @Test("String lstrip with non-string chars throws")
    func stringLstripNonStringChars() throws {
        let value = Value.string("  hello  ")
        let result = try PropertyMembers.evaluate(value, "lstrip")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        #expect(throws: JinjaError.self) {
            _ = try fn([.boolean(true)], [:], Environment())
        }
    }

    @Test("String rstrip with non-string chars throws")
    func stringRstripNonStringChars() throws {
        let value = Value.string("  hello  ")
        let result = try PropertyMembers.evaluate(value, "rstrip")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        #expect(throws: JinjaError.self) {
            _ = try fn([.int(0)], [:], Environment())
        }
    }

    @Test("String strip rejects extra arguments")
    func stringStripRejectsExtraArguments() throws {
        let value = Value.string("hello")
        let result = try PropertyMembers.evaluate(value, "strip")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        #expect(throws: JinjaError.self) {
            _ = try fn([.string("x"), .string("y")], [:], Environment())
        }
    }

    @Test("String lstrip rejects extra arguments")
    func stringLstripRejectsExtraArguments() throws {
        let value = Value.string("hello")
        let result = try PropertyMembers.evaluate(value, "lstrip")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        #expect(throws: JinjaError.self) {
            _ = try fn([.string("/"), .string("x")], [:], Environment())
        }
    }

    @Test("String rstrip rejects extra arguments")
    func stringRstripRejectsExtraArguments() throws {
        let value = Value.string("hello")
        let result = try PropertyMembers.evaluate(value, "rstrip")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        #expect(throws: JinjaError.self) {
            _ = try fn([.string("."), .string("x")], [:], Environment())
        }
    }

    @Test("String split without separator")
    func stringSplitDefault() throws {
        let value = Value.string("hello world test")
        let result = try PropertyMembers.evaluate(value, "split")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let splitResult = try fn([], [:], Environment())
        let expected = Value.array([.string("hello"), .string("world"), .string("test")])
        #expect(splitResult == expected)
    }

    @Test("String split with separator")
    func stringSplitWithSeparator() throws {
        let value = Value.string("a,b,c,d")
        let result = try PropertyMembers.evaluate(value, "split")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let splitResult = try fn([.string(",")], [:], Environment())
        let expected = Value.array([.string("a"), .string("b"), .string("c"), .string("d")])
        #expect(splitResult == expected)
    }

    @Test("String split with separator and limit")
    func stringSplitWithLimit() throws {
        let value = Value.string("a,b,c,d")
        let result = try PropertyMembers.evaluate(value, "split")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let splitResult = try fn([.string(","), .int(2)], [:], Environment())
        let expected = Value.array([.string("a"), .string("b"), .string("c,d")])
        #expect(splitResult == expected)
    }

    @Test("String replace basic")
    func stringReplaceBasic() throws {
        let value = Value.string("hello world")
        let result = try PropertyMembers.evaluate(value, "replace")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let replaceResult = try fn([.string("world"), .string("universe")], [:], Environment())
        #expect(replaceResult == .string("hello universe"))
    }

    @Test("String replace with count argument")
    func stringReplaceWithCount() throws {
        let value = Value.string("test test test")
        let result = try PropertyMembers.evaluate(value, "replace")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let replaceResult = try fn(
            [.string("test"), .string("hello"), .int(2)],
            [:],
            Environment()
        )
        #expect(replaceResult == .string("hello hello test"))
    }

    @Test("String replace with count kwarg")
    func stringReplaceWithCountKwarg() throws {
        let value = Value.string("test test test")
        let result = try PropertyMembers.evaluate(value, "replace")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let replaceResult = try fn(
            [.string("test"), .string("hello")],
            ["count": .int(1)],
            Environment()
        )
        #expect(replaceResult == .string("hello test test"))
    }

    @Test("String replace empty string")
    func stringReplaceEmpty() throws {
        let value = Value.string("abc")
        let result = try PropertyMembers.evaluate(value, "replace")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let replaceResult = try fn([.string(""), .string("_")], [:], Environment())
        #expect(replaceResult == .string("_a_b_c_"))
    }

    @Test("String replace empty string with limit")
    func stringReplaceEmptyWithLimit() throws {
        let value = Value.string("abc")
        let result = try PropertyMembers.evaluate(value, "replace")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let replaceResult = try fn([.string(""), .string("_"), .int(2)], [:], Environment())
        #expect(replaceResult == .string("_a_bc"))
    }

    @Test("String startswith true")
    func stringStartswithTrue() throws {
        let value = Value.string("hello world")
        let result = try PropertyMembers.evaluate(value, "startswith")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let startsResult = try fn([.string("hello")], [:], Environment())
        #expect(startsResult == .boolean(true))
    }

    @Test("String startswith false")
    func stringStartswithFalse() throws {
        let value = Value.string("hello world")
        let result = try PropertyMembers.evaluate(value, "startswith")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let startsResult = try fn([.string("world")], [:], Environment())
        #expect(startsResult == .boolean(false))
    }

    @Test("String endswith true")
    func stringEndswithTrue() throws {
        let value = Value.string("hello world")
        let result = try PropertyMembers.evaluate(value, "endswith")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let endsResult = try fn([.string("world")], [:], Environment())
        #expect(endsResult == .boolean(true))
    }

    @Test("String endswith false")
    func stringEndswithFalse() throws {
        let value = Value.string("hello world")
        let result = try PropertyMembers.evaluate(value, "endswith")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let endsResult = try fn([.string("hello")], [:], Environment())
        #expect(endsResult == .boolean(false))
    }

    @Test("String undefined property")
    func stringUndefinedProperty() throws {
        let value = Value.string("test")
        let result = try PropertyMembers.evaluate(value, "nonexistent")
        #expect(result == .undefined)
    }

    // MARK: - Object Property Tests

    @Test("Object items method")
    func objectItems() throws {
        let dict: OrderedDictionary<ObjectKey, Value> = ["a": .int(1), "b": .int(2)]
        let value = Value.object(dict)
        let result = try PropertyMembers.evaluate(value, "items")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let itemsResult = try fn([], [:], Environment())
        let expected = Value.array([
            .array([.string("a"), .int(1)]),
            .array([.string("b"), .int(2)]),
        ])
        #expect(itemsResult == expected)
    }

    @Test("Object get method with existing key")
    func objectGetExisting() throws {
        let dict: OrderedDictionary<ObjectKey, Value> = ["name": .string("John"), "age": .int(30)]
        let value = Value.object(dict)
        let result = try PropertyMembers.evaluate(value, "get")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let getResult = try fn([.string("name")], [:], Environment())
        #expect(getResult == .string("John"))
    }

    @Test("Object get method with missing key")
    func objectGetMissing() throws {
        let dict: OrderedDictionary<ObjectKey, Value> = ["name": .string("John")]
        let value = Value.object(dict)
        let result = try PropertyMembers.evaluate(value, "get")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let getResult = try fn([.string("missing")], [:], Environment())
        #expect(getResult == .null)
    }

    @Test("Object get method with default value")
    func objectGetWithDefault() throws {
        let dict: OrderedDictionary<ObjectKey, Value> = ["name": .string("John")]
        let value = Value.object(dict)
        let result = try PropertyMembers.evaluate(value, "get")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let getResult = try fn([.string("missing"), .string("default")], [:], Environment())
        #expect(getResult == .string("default"))
    }

    @Test("Object get method with integer key")
    func objectGetIntegerKey() throws {
        let dict: OrderedDictionary<ObjectKey, Value> = [42: .string("answer")]
        let value = Value.object(dict)
        let result = try PropertyMembers.evaluate(value, "get")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let getResult = try fn([.int(42)], [:], Environment())
        #expect(getResult == .string("answer"))

        // Integer keys are distinct from their string representations.
        let missing = try fn([.string("42")], [:], Environment())
        #expect(missing == .null)
    }

    @Test("Object keys method")
    func objectKeys() throws {
        let dict: OrderedDictionary<ObjectKey, Value> = ["a": .int(1), "b": .int(2), "c": .int(3)]
        let value = Value.object(dict)
        let result = try PropertyMembers.evaluate(value, "keys")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let keysResult = try fn([], [:], Environment())
        let expected = Value.array([.string("a"), .string("b"), .string("c")])
        #expect(keysResult == expected)
    }

    @Test("Object values method")
    func objectValues() throws {
        let dict: OrderedDictionary<ObjectKey, Value> = ["a": .int(1), "b": .int(2), "c": .int(3)]
        let value = Value.object(dict)
        let result = try PropertyMembers.evaluate(value, "values")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let valuesResult = try fn([], [:], Environment())
        let expected = Value.array([.int(1), .int(2), .int(3)])
        #expect(valuesResult == expected)
    }

    @Test("Object direct property access")
    func objectDirectProperty() throws {
        let dict: OrderedDictionary<ObjectKey, Value> = ["foo": .string("bar")]
        let value = Value.object(dict)
        let result = try PropertyMembers.evaluate(value, "foo")
        #expect(result == .string("bar"))
    }

    @Test("Object undefined property")
    func objectUndefinedProperty() throws {
        let dict: OrderedDictionary<ObjectKey, Value> = ["foo": .string("bar")]
        let value = Value.object(dict)
        let result = try PropertyMembers.evaluate(value, "nonexistent")
        #expect(result == .undefined)
    }

    // MARK: - Other Value Type Tests

    @Test("Non-string non-object value")
    func nonStringNonObjectValue() throws {
        let value = Value.int(42)
        let result = try PropertyMembers.evaluate(value, "someProperty")
        #expect(result == .undefined)
    }

    @Test("Null value property access")
    func nullValueProperty() throws {
        let value = Value.null
        let result = try PropertyMembers.evaluate(value, "someProperty")
        #expect(result == .undefined)
    }

    @Test("Array value property access")
    func arrayValueProperty() throws {
        let value = Value.array([.int(1), .int(2), .int(3)])
        let result = try PropertyMembers.evaluate(value, "someProperty")
        #expect(result == .undefined)
    }

    // MARK: - Object get with no key argument

    @Test("Object get with no key argument throws")
    func objectGetNoKey() throws {
        let dict: OrderedDictionary<ObjectKey, Value> = ["a": .int(1)]
        let value = Value.object(dict)
        let result = try PropertyMembers.evaluate(value, "get")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        #expect(throws: JinjaError.self) {
            _ = try fn([], [:], Environment())
        }
    }

    // MARK: - String startswith with non-string prefix

    @Test("String startswith with non-string prefix throws")
    func stringStartswithNonString() throws {
        let value = Value.string("hello")
        let result = try PropertyMembers.evaluate(value, "startswith")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        #expect(throws: JinjaError.self) {
            _ = try fn([.int(42)], [:], Environment())
        }
    }

    // MARK: - String endswith with non-string suffix

    @Test("String endswith with non-string suffix throws")
    func stringEndswithNonString() throws {
        let value = Value.string("hello")
        let result = try PropertyMembers.evaluate(value, "endswith")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        #expect(throws: JinjaError.self) {
            _ = try fn([.int(42)], [:], Environment())
        }
    }

    // MARK: - String replace with non-string arguments

    @Test("String replace with non-string old throws")
    func stringReplaceNonStringOld() throws {
        let value = Value.string("hello")
        let result = try PropertyMembers.evaluate(value, "replace")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        #expect(throws: JinjaError.self) {
            _ = try fn([.int(1), .string("x")], [:], Environment())
        }
    }

    // MARK: - Boolean value property access

    @Test("Boolean value property access")
    func booleanValueProperty() throws {
        let value = Value.boolean(true)
        let result = try PropertyMembers.evaluate(value, "someProperty")
        #expect(result == .undefined)
    }

    // MARK: - Function value property access

    @Test("Function value property access")
    func functionValueProperty() throws {
        let value = Value.function { _, _, _ in .null }
        let result = try PropertyMembers.evaluate(value, "someProperty")
        #expect(result == .undefined)
    }

    // MARK: - String format and join

    // Expected values come from Jinja2 3.1.6.
    @Test(
        "String format and join match Jinja2",
        arguments: [
            ("{{ '{} and {}'.format('a', 'b') }}", "a and b"),
            ("{{ '{1}{0}{1}'.format('a', 'b') }}", "bab"),
            ("{{ '{x}-{y}'.format(x=1, y=2.5) }}", "1-2.5"),
            ("{{ '{{}} {{{}}}'.format(1) }}", "{} {1}"),
            ("{{ '<｜hy_eos{}｜>'.format(':opensource') }}", "<｜hy_eos:opensource｜>"),
            ("{{ '{}|{}|{}'.format(true, false, none) }}", "True|False|None"),
            (
                "{{ '{}|{}|{}|{}'.format(10000000000000000.0, 0.1, 1.0, 1234567890123456.0) }}",
                "1e+16|0.1|1.0|1234567890123456.0"
            ),
            ("{{ '{}'.format([1, 'a', true, none, 1.5]) }}", "[1, 'a', True, None, 1.5]"),
            ("{{ '{}'.format({'a': [1], 2: \"it's\"}) }}", "{'a': [1], 2: \"it's\"}"),
            ("{{ '{}'.format(['a\"b', 'g\\nh\\\\']) }}", "['a\"b', 'g\\nh\\\\']"),
            ("{{ '[{}]'.format(missing) }}", "[]"),
            ("{{ '{0!r}|{0!s}|{0:}'.format('a') }}", "'a'|a|a"),
            ("{{ '{!r}'.format('a\\nb') }}", "'a\\nb'"),
            ("{{ '{!r}'.format('\u{00A0}\u{200B}\u{7F}é') }}", "'\\xa0\\u200b\\x7fé'"),
            ("{% macro m() %}{% endmacro %}{{ '{}'.format(m) }}", "<Macro 'm'>"),
            ("{{ '{}'.format('x', 'y', z=1) }}", "x"),
            ("{{ ', '.join(['a', 'b']) }}", "a, b"),
            ("{{ '-'.join('abc') }}", "a-b-c"),
            ("{{ '-'.join({'a': 1, 'b': 2}) }}", "a-b"),
            ("{{ '[' ~ ''.join([]) ~ ']' }}", "[]"),
            ("{{ ''.join(['c', 'A', 'b', 'D']|sort) }}", "AbcD"),
        ]
    )
    func stringFormatAndJoin(source: String, expected: String) throws {
        #expect(try Template(source).render([:]) == expected)
    }

    // Jinja2 3.1.6 raises for each of these, except the first three:
    // swift-jinja rejects format specs, the `!a` conversion, and attribute access
    // instead of rendering them differently.
    @Test(
        "String format and join reject invalid or unsupported input",
        arguments: [
            ("{{ '{:>10}'.format(1) }}", "format() doesn't support the format spec ':>10'"),
            ("{{ '{!a}'.format(1) }}", "format() doesn't support the conversion '!a'"),
            ("{{ '{0.real}'.format(1) }}", "format() doesn't support attribute or item access in field '{0.real}'"),
            (
                "{{ '{0} {}'.format(1, 2) }}",
                "cannot switch from manual field specification to automatic field numbering"
            ),
            (
                "{{ '{} {0}'.format(1, 2) }}",
                "cannot switch from automatic field numbering to manual field specification"
            ),
            ("{{ '{2}'.format(1) }}", "Replacement index 2 out of range for positional args tuple"),
            ("{{ '{x}'.format() }}", "format() is missing keyword argument 'x'"),
            ("{{ 'a}b'.format() }}", "Single '}' encountered in format string"),
            ("{{ 'a{b'.format() }}", "expected '}' before end of string"),
            ("{{ '{!rr}'.format(1) }}", "expected ':' after conversion specifier"),
            ("{{ ','.join([1]) }}", "join() sequence item 0: expected a string"),
            ("{{ ','.join('a', 'b') }}", "join() takes exactly one argument (2 given)"),
            ("{{ ','.join(iterable=['a']) }}", "join() takes no keyword arguments"),
            ("{{ ','.join(none) }}", "join() can only join an iterable"),
        ]
    )
    func stringFormatAndJoinErrors(source: String, message: String) throws {
        let template = try Template(source)
        do {
            _ = try template.render([:])
            Issue.record("Expected a runtime error for \(source)")
        } catch JinjaError.runtime(let thrown) {
            #expect(thrown == message)
        }
    }

    @Test("String format rejects a function value")
    func stringFormatFunction() throws {
        let template = try Template("{{ '{}'.format(f) }}")
        do {
            _ = try template.render(["f": .function { _, _, _ in .null }])
            Issue.record("Expected a runtime error")
        } catch JinjaError.runtime(let message) {
            #expect(message == "format() can't convert a function to a string")
        }
    }
}
