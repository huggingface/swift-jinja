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
        let dict: OrderedDictionary<String, Value> = ["a": .int(1), "b": .int(2)]
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
        let dict: OrderedDictionary<String, Value> = ["name": .string("John"), "age": .int(30)]
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
        let dict: OrderedDictionary<String, Value> = ["name": .string("John")]
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
        let dict: OrderedDictionary<String, Value> = ["name": .string("John")]
        let value = Value.object(dict)
        let result = try PropertyMembers.evaluate(value, "get")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let getResult = try fn([.string("missing"), .string("default")], [:], Environment())
        #expect(getResult == .string("default"))
    }

    @Test("Object get method with non-string key")
    func objectGetNonStringKey() throws {
        let dict: OrderedDictionary<String, Value> = ["42": .string("answer")]
        let value = Value.object(dict)
        let result = try PropertyMembers.evaluate(value, "get")

        guard case let .function(fn) = result else {
            Issue.record("Expected function")
            return
        }

        let getResult = try fn([.int(42)], [:], Environment())
        #expect(getResult == .string("answer"))
    }

    @Test("Object direct property access")
    func objectDirectProperty() throws {
        let dict: OrderedDictionary<String, Value> = ["foo": .string("bar")]
        let value = Value.object(dict)
        let result = try PropertyMembers.evaluate(value, "foo")
        #expect(result == .string("bar"))
    }

    @Test("Object undefined property")
    func objectUndefinedProperty() throws {
        let dict: OrderedDictionary<String, Value> = ["foo": .string("bar")]
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
}
