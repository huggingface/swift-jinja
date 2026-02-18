import Foundation
import Testing

@testable import Jinja

@Suite("Filters Tests")
struct FiltersTests {
    let env = Environment()

    @Test("upper filter")
    func upperFilter() throws {
        let result = try Filters.upper([.string("hello world")], kwargs: [:], env: env)
        #expect(result == .string("HELLO WORLD"))
    }

    @Test("lower filter")
    func lowerFilter() throws {
        let result = try Filters.lower([.string("HELLO WORLD")], kwargs: [:], env: env)
        #expect(result == .string("hello world"))
    }

    @Test("length filter for strings")
    func lengthFilterString() throws {
        let result = try Filters.length([.string("hello")], kwargs: [:], env: env)
        #expect(result == .int(5))
    }

    @Test("length filter for arrays")
    func lengthFilterArray() throws {
        let values = [Value.int(1), .int(2), .int(3)]
        let result = try Filters.length([.array(values)], kwargs: [:], env: env)
        #expect(result == .int(3))
    }

    @Test("length filter for undefined")
    func lengthFilterUndefined() throws {
        let result = try Filters.length([.undefined], kwargs: [:], env: env)
        #expect(result == .int(0))
    }

    @Test("join filter")
    func joinFilter() throws {
        let values = [Value.string("a"), .string("b"), .string("c")]
        let result = try Filters.join([.array(values), .string(", ")], kwargs: [:], env: env)
        #expect(result == .string("a, b, c"))
    }

    @Test("join filter with attribute")
    func joinFilterWithAttribute() throws {
        let values: [Value] = [
            .object(["name": .string("a")]),
            .object(["name": .string("b")]),
        ]
        let result = try Filters.join(
            [.array(values), .string(", "), .string("name")],
            kwargs: [:],
            env: env
        )
        #expect(result == .string("a, b"))
    }

    @Test("join filter with integer attribute")
    func joinFilterWithIntegerAttribute() throws {
        let values: [Value] = [
            .array([.string("a"), .string("b")]),
            .array([.string("c"), .string("d")]),
        ]
        let result = try Filters.join(
            [.array(values), .string(", "), .int(1)],
            kwargs: [:],
            env: env
        )
        #expect(result == .string("b, d"))
    }

    @Test("default filter alias d")
    func defaultFilterAlias() throws {
        guard let fn = Filters.builtIn["d"] else {
            Issue.record("Expected default alias 'd' to be registered")
            return
        }
        let result = try fn([.undefined, .string("fallback")], [:], env)
        #expect(result == .string("fallback"))
    }

    @Test("default filter with undefined")
    func defaultFilterWithUndefined() throws {
        let result = try Filters.default(
            [.undefined, .string("fallback")],
            kwargs: [:],
            env: env
        )
        #expect(result == .string("fallback"))
    }

    @Test("default filter with defined value")
    func defaultFilterWithDefinedValue() throws {
        let result = try Filters.default(
            [.string("actual"), .string("fallback")],
            kwargs: [:],
            env: env
        )
        #expect(result == .string("actual"))
    }

    @Test("first filter with array")
    func firstFilterWithArray() throws {
        let values = [Value.string("a"), .string("b"), .string("c")]
        let result = try Filters.first([.array(values)], kwargs: [:], env: env)
        #expect(result == .string("a"))
    }

    @Test("last filter with array")
    func lastFilterWithArray() throws {
        let values = [Value.string("a"), .string("b"), .string("c")]
        let result = try Filters.last([.array(values)], kwargs: [:], env: env)
        #expect(result == .string("c"))
    }

    @Test("reverse filter with array")
    func reverseFilterWithArray() throws {
        let values = [Value.int(1), .int(2), .int(3)]
        let result = try Filters.reverse([.array(values)], kwargs: [:], env: env)
        let expected = Value.array([.int(3), .int(2), .int(1)])
        #expect(result == expected)
    }

    @Test("abs filter with negative integer")
    func absFilterWithNegativeInteger() throws {
        let result = try Filters.abs([.int(-5)], kwargs: [:], env: env)
        #expect(result == .int(5))
    }

    @Test("abs filter with negative number")
    func absFilterWithNegativeNumber() throws {
        let result = try Filters.abs([.double(-3.14)], kwargs: [:], env: env)
        #expect(result == .double(3.14))
    }

    @Test("capitalize filter")
    func capitalizeFilter() throws {
        let result = try Filters.capitalize([.string("hello world")], kwargs: [:], env: env)
        #expect(result == .string("Hello world"))
    }

    @Test("trim filter")
    func trimFilter() throws {
        let result = try Filters.trim([.string("  hello world  ")], kwargs: [:], env: env)
        #expect(result == .string("hello world"))
    }

    @Test("trim filter with chars")
    func trimFilterWithChars() throws {
        let result = try Filters.trim([.string("--hello--"), .string("-")], kwargs: [:], env: env)
        #expect(result == .string("hello"))
    }

    @Test("float filter")
    func floatFilter() throws {
        let result = try Filters.float([.int(42)], kwargs: [:], env: env)
        #expect(result == .double(42.0))
    }

    @Test("int filter")
    func intFilter() throws {
        let result = try Filters.int([.double(3.14)], kwargs: [:], env: env)
        #expect(result == .int(3))
    }

    @Test("int filter with base and prefix")
    func intFilterWithBaseAndPrefix() throws {
        let prefixed = try Filters.int([.string("0x10")], kwargs: [:], env: env)
        #expect(prefixed == .int(16))

        let baseResult = try Filters.int(
            [.string("ff"), .int(0), .int(16)],
            kwargs: [:],
            env: env
        )
        #expect(baseResult == .int(255))
    }

    @Test("unique filter")
    func uniqueFilter() throws {
        let values = [Value.int(1), .int(2), .int(1), .int(3), .int(2)]
        let result = try Filters.unique([.array(values)], kwargs: [:], env: env)
        let expected = Value.array([.int(1), .int(2), .int(3)])
        #expect(result == expected)
    }

    @Test("unique filter with case sensitivity and attribute")
    func uniqueFilterWithCaseSensitiveAndAttribute() throws {
        let values = [Value.string("A"), .string("a")]
        let result = try Filters.unique([.array(values)], kwargs: [:], env: env)
        #expect(result == .array([.string("A")]))

        let objects: [Value] = [
            .object(["id": .int(1)]),
            .object(["id": .int(1)]),
            .object(["id": .int(2)]),
        ]
        let attributeResult = try Filters.unique(
            [.array(objects)],
            kwargs: ["attribute": .string("id")],
            env: env
        )
        #expect(attributeResult == .array([objects[0], objects[2]]))

        let listItems: [Value] = [
            .array([.int(1), .int(10)]),
            .array([.int(1), .int(20)]),
            .array([.int(2), .int(30)]),
        ]
        let indexResult = try Filters.unique(
            [.array(listItems)],
            kwargs: ["attribute": .int(0)],
            env: env
        )
        #expect(indexResult == .array([listItems[0], listItems[2]]))
    }

    @Test("groupby filter with default and case-insensitive")
    func groupbyFilterWithDefaultAndCaseInsensitive() throws {
        let items: [Value] = [
            .object(["city": .string("NY")]),
            .object(["city": .string("CA")]),
            .object(["city": .string("ca")]),
        ]
        let result = try Filters.groupby([.array(items), .string("city")], kwargs: [:], env: env)
        guard case let .array(groups) = result else {
            Issue.record("Expected array result")
            return
        }
        #expect(groups.count == 2)

        if case let .object(group) = groups.first {
            #expect(group["list"] == .array([items[1], items[2]]))
        } else {
            Issue.record("Expected object group result")
        }

        let defaultResult = try Filters.groupby(
            [.array([.object(["name": .string("a")])]), .string("city")],
            kwargs: ["default": .string("Unknown")],
            env: env
        )
        if case let .array(defaultGroups) = defaultResult,
            case let .object(group) = defaultGroups.first
        {
            #expect(group["grouper"] == .string("Unknown"))
        } else {
            Issue.record("Expected default group result")
        }
    }

    @Test("map filter with default")
    func mapFilterWithDefault() throws {
        let items: [Value] = [
            .object(["name": .string("a")]),
            .object(["other": .string("b")]),
        ]
        let result = try Filters.map(
            [.array(items)],
            kwargs: ["attribute": .string("name"), "default": .string("n/a")],
            env: env
        )
        #expect(result == .array([.string("a"), .string("n/a")]))
    }

    @Test("map filter with integer attribute")
    func mapFilterWithIntegerAttribute() throws {
        let items: [Value] = [
            .array([.string("a"), .string("b")]),
            .array([.string("c"), .string("d")]),
        ]
        let result = try Filters.map(
            [.array(items)],
            kwargs: ["attribute": .int(0)],
            env: env
        )
        #expect(result == .array([.string("a"), .string("c")]))
    }

    @Test("max/min filter with case sensitivity")
    func maxMinFilterWithCaseSensitivity() throws {
        let values = [Value.string("a"), .string("B")]
        let maxValue = try Filters.max([.array(values), .boolean(false)], kwargs: [:], env: env)
        let minValue = try Filters.min([.array(values), .boolean(false)], kwargs: [:], env: env)
        #expect(maxValue == .string("B"))
        #expect(minValue == .string("a"))
    }

    @Test("sort filter with attribute list")
    func sortFilterWithAttributeList() throws {
        let items: [Value] = [
            .object(["age": .int(2), "name": .string("b")]),
            .object(["age": .int(1), "name": .string("c")]),
            .object(["age": .int(1), "name": .string("a")]),
        ]
        let result = try Filters.sort(
            [.array(items), .boolean(false), .boolean(false), .string("age,name")],
            kwargs: [:],
            env: env
        )
        guard case let .array(sorted) = result else {
            Issue.record("Expected array result")
            return
        }
        let names = try sorted.map { value in
            let name = try PropertyMembers.evaluate(value, "name")
            return name
        }
        #expect(names == [.string("a"), .string("c"), .string("b")])
    }

    @Test("truncate filter with leeway")
    func truncateFilterWithLeeway() throws {
        let result = try Filters.truncate(
            [.string("abcdefghij"), .int(8), .boolean(false), .string("..."), .int(3)],
            kwargs: [:],
            env: env
        )
        #expect(result == .string("abcdefghij"))
    }

    @Test("wordwrap filter with wrapstring")
    func wordwrapFilterWithWrapstring() throws {
        let result = try Filters.wordwrap(
            [.string("one two three"), .int(5), .boolean(true), .string("|"), .boolean(true)],
            kwargs: [:],
            env: env
        )
        #expect(result == .string("one|two|three"))
    }

    @Test("dictsort filter")
    func dictsortFilter() throws {
        let dict = Value.object(["c": .int(3), "a": .int(1), "b": .int(2)])
        let result = try Filters.dictsort([dict], kwargs: [:], env: env)
        let expected = Value.array([
            .array([.string("a"), .int(1)]),
            .array([.string("b"), .int(2)]),
            .array([.string("c"), .int(3)]),
        ])
        #expect(result == expected)
    }

    @Test("dictsort filter with reverse")
    func dictsortFilterWithReverse() throws {
        let dict = Value.object(["b": .int(2), "a": .int(1)])
        let result = try Filters.dictsort(
            [dict, .boolean(false), .string("key"), .boolean(true)],
            kwargs: [:],
            env: env
        )
        let expected = Value.array([
            .array([.string("b"), .int(2)]),
            .array([.string("a"), .int(1)]),
        ])
        #expect(result == expected)
    }

    @Test("pprint filter")
    func pprintFilter() throws {
        let dict = Value.object(["name": .string("test"), "value": .int(42)])
        let result = try Filters.pprint([dict], kwargs: [:], env: env)
        // Just check it's a string (exact format may vary)
        if case .string(let str) = result {
            #expect(str.contains("name"))
            #expect(str.contains("test"))
            #expect(str.contains("value"))
            #expect(str.contains("42"))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("urlize filter")
    func urlizeFilter() throws {
        let text = "Visit https://example.com for more info"
        let result = try Filters.urlize([.string(text)], kwargs: [:], env: env)
        if case .string(let str) = result {
            #expect(str.contains("<a href=\"https://example.com\">"))
            #expect(str.contains("</a>"))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("urlize filter with extra schemes and emails")
    func urlizeFilterWithExtraSchemesAndEmails() throws {
        let text = "Use ftp://example.com or contact me@example.com"
        let result = try Filters.urlize(
            [.string(text)],
            kwargs: ["extra_schemes": .array([.string("ftp")])],
            env: env
        )
        if case .string(let str) = result {
            #expect(str.contains("<a href=\"ftp://example.com\">"))
            #expect(str.contains("<a href=\"mailto:me@example.com\">"))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("urlencode filter for string and mapping")
    func urlencodeFilterForStringAndMapping() throws {
        let stringResult = try Filters.urlencode([.string("/path with space")], kwargs: [:], env: env)
        #expect(stringResult == .string("/path%20with%20space"))

        let dict = Value.object(["a": .string("b c")])
        let dictResult = try Filters.urlencode([dict], kwargs: [:], env: env)
        #expect(dictResult == .string("a=b%20c"))
    }

    @Test("sum filter with attribute")
    func sumFilterWithAttribute() throws {
        let items = Value.array([
            .object(["price": .double(10.5)]),
            .object(["price": .double(20.0)]),
            .object(["price": .double(15.5)]),
        ])
        let result = try Filters.sum([items, .string("price")], kwargs: [:], env: env)
        #expect(result == .double(46.0))
    }

    @Test("indent filter")
    func indentFilter() throws {
        let text = "line1\nline2\nline3"
        let result = try Filters.indent([.string(text), .int(2)], kwargs: [:], env: env)
        if case .string(let str) = result {
            // First line is NOT indented by default
            #expect(str.hasPrefix("line1"))
            #expect(str.contains("  line2"))
            #expect(str.contains("  line3"))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("indent filter with first")
    func indentFilterWithFirst() throws {
        let text = "line1\nline2\nline3"
        let result = try Filters.indent(
            [.string(text), .int(2), .boolean(true)],
            kwargs: [:],
            env: env
        )
        if case .string(let str) = result {
            // All lines should be indented when first=true
            #expect(str.contains("  line1"))
            #expect(str.contains("  line2"))
            #expect(str.contains("  line3"))
        } else {
            Issue.record("Expected string result")
        }
    }

    // MARK: - tojson filter tests

    @Test("tojson filter with ASCII string")
    func tojsonFilterWithASCIIString() throws {
        let result = try Filters.tojson([.string("hello")], kwargs: [:], env: env)
        #expect(result == .string("\"hello\""))
    }

    @Test("tojson filter with integer")
    func tojsonFilterWithInteger() throws {
        let result = try Filters.tojson([.int(42)], kwargs: [:], env: env)
        #expect(result == .string("42"))
    }

    @Test("tojson filter with boolean")
    func tojsonFilterWithBoolean() throws {
        let result = try Filters.tojson([.boolean(true)], kwargs: [:], env: env)
        #expect(result == .string("true"))
    }

    @Test("tojson filter with null")
    func tojsonFilterWithNull() throws {
        let result = try Filters.tojson([.null], kwargs: [:], env: env)
        #expect(result == .string("null"))
    }

    @Test("tojson filter with array")
    func tojsonFilterWithArray() throws {
        let result = try Filters.tojson([.array([.int(1), .int(2), .int(3)])], kwargs: [:], env: env)
        #expect(result == .string("[1,2,3]"))
    }

    @Test("tojson filter escapes non-ASCII by default")
    func tojsonFilterEscapesNonASCIIByDefault() throws {
        // Chinese characters "你好" should be escaped as \uXXXX by default
        let result = try Filters.tojson([.string("你好")], kwargs: [:], env: env)
        if case .string(let str) = result {
            #expect(str.contains("\\u4f60"))  // 你
            #expect(str.contains("\\u597d"))  // 好
            #expect(!str.contains("你"))
            #expect(!str.contains("好"))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("tojson filter with ensure_ascii=true")
    func tojsonFilterWithEnsureASCIITrue() throws {
        let result = try Filters.tojson(
            [.string("你好")],
            kwargs: ["ensure_ascii": .boolean(true)],
            env: env
        )
        if case .string(let str) = result {
            #expect(str.contains("\\u4f60"))
            #expect(str.contains("\\u597d"))
            #expect(!str.contains("你"))
            #expect(!str.contains("好"))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("tojson filter with ensure_ascii=true escapes emoji")
    func tojsonFilterWithEnsureASCIITrueEscapesEmoji() throws {
        let result = try Filters.tojson(
            [.string("Hello 😀")],
            kwargs: ["ensure_ascii": .boolean(true)],
            env: env
        )
        if case .string(let str) = result {
            #expect(str.contains("Hello"))
            #expect(str.contains("\\ud83d\\ude00"))
            #expect(!str.contains("😀"))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("tojson filter with ensure_ascii=false preserves Unicode")
    func tojsonFilterWithEnsureASCIIFalse() throws {
        // When ensure_ascii=false, Unicode characters should be preserved
        let result = try Filters.tojson(
            [.string("你好")],
            kwargs: ["ensure_ascii": .boolean(false)],
            env: env
        )
        if case .string(let str) = result {
            #expect(str.contains("你"))
            #expect(str.contains("好"))
            #expect(!str.contains("\\u4f60"))
            #expect(!str.contains("\\u597d"))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("tojson filter with ensure_ascii=false in object")
    func tojsonFilterWithEnsureASCIIFalseInObject() throws {
        // Test object with Chinese characters and ensure_ascii=false
        let obj = Value.object(["name": .string("测试"), "value": .int(123)])
        let result = try Filters.tojson(
            [obj],
            kwargs: ["ensure_ascii": .boolean(false)],
            env: env
        )
        if case .string(let str) = result {
            #expect(str.contains("测试"))
            #expect(str.contains("123"))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("tojson filter with indent and ensure_ascii=false")
    func tojsonFilterWithIndentAndEnsureASCIIFalse() throws {
        // Test combining indent and ensure_ascii parameters
        let obj = Value.object(["name": .string("你好")])
        let result = try Filters.tojson(
            [obj],
            kwargs: ["indent": .int(2), "ensure_ascii": .boolean(false)],
            env: env
        )
        if case .string(let str) = result {
            #expect(str.contains("你好"))
            #expect(str.contains("\n"))  // Pretty printed should have newlines
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("tojson filter with mixed ASCII and non-ASCII")
    func tojsonFilterWithMixedContent() throws {
        let result = try Filters.tojson(
            [.string("Hello 世界!")],
            kwargs: ["ensure_ascii": .boolean(true)],
            env: env
        )
        if case .string(let str) = result {
            #expect(str.contains("Hello"))
            #expect(str.contains("!"))
            #expect(str.contains("\\u4e16"))  // 世
            #expect(str.contains("\\u754c"))  // 界
            #expect(!str.contains("世"))
            #expect(!str.contains("界"))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("tojson filter GLM template use case")
    func tojsonFilterGLMTemplateUseCase() throws {
        // Simulate the GLM model template use case with tool containing Chinese
        let tool = Value.object([
            "type": .string("function"),
            "function": .object([
                "name": .string("search"),
                "description": .string("搜索信息"),
            ]),
        ])
        let result = try Filters.tojson(
            [tool],
            kwargs: ["ensure_ascii": .boolean(false)],
            env: env
        )
        if case .string(let str) = result {
            #expect(str.contains("搜索信息"))
            #expect(str.contains("function"))
            #expect(str.contains("search"))
        } else {
            Issue.record("Expected string result")
        }
    }

    // MARK: - Error/Edge Case Coverage

    @Test("upper filter with non-string throws")
    func upperFilterNonString() throws {
        #expect(throws: JinjaError.self) {
            try Filters.upper([.int(42)], kwargs: [:], env: env)
        }
    }

    @Test("lower filter with non-string throws")
    func lowerFilterNonString() throws {
        #expect(throws: JinjaError.self) {
            try Filters.lower([.int(42)], kwargs: [:], env: env)
        }
    }

    @Test("length filter for objects")
    func lengthFilterObject() throws {
        let result = try Filters.length([.object(["a": .int(1), "b": .int(2)])], kwargs: [:], env: env)
        #expect(result == .int(2))
    }

    @Test("length filter for non-supported type throws")
    func lengthFilterNonSupported() throws {
        #expect(throws: JinjaError.self) {
            try Filters.length([.int(42)], kwargs: [:], env: env)
        }
    }

    @Test("join filter with non-array throws")
    func joinFilterNonArray() throws {
        #expect(throws: JinjaError.self) {
            try Filters.join([.int(42), .string(",")], kwargs: [:], env: env)
        }
    }

    @Test("join filter with non-string separator throws")
    func joinFilterNonStringSeparator() throws {
        #expect(throws: JinjaError.self) {
            try Filters.join([.array([.int(1)]), .int(42)], kwargs: [:], env: env)
        }
    }

    @Test("default filter with boolean mode")
    func defaultFilterBooleanMode() throws {
        let result = try Filters.default(
            [.boolean(false), .string("fallback")],
            kwargs: ["boolean": .boolean(true)],
            env: env
        )
        #expect(result == .string("fallback"))
    }

    @Test("first filter with no args")
    func firstFilterNoArgs() throws {
        let result = try Filters.first([], kwargs: [:], env: env)
        #expect(result == .undefined)
    }

    @Test("first filter with empty array")
    func firstFilterEmptyArray() throws {
        let result = try Filters.first([.array([])], kwargs: [:], env: env)
        #expect(result == .undefined)
    }

    @Test("first filter with string")
    func firstFilterString() throws {
        let result = try Filters.first([.string("abc")], kwargs: [:], env: env)
        #expect(result == .string("a"))
    }

    @Test("first filter with empty string")
    func firstFilterEmptyString() throws {
        let result = try Filters.first([.string("")], kwargs: [:], env: env)
        #expect(result == .undefined)
    }

    @Test("first filter with non-array/string throws")
    func firstFilterNonArrayString() throws {
        #expect(throws: JinjaError.self) {
            try Filters.first([.int(42)], kwargs: [:], env: env)
        }
    }

    @Test("last filter with no args")
    func lastFilterNoArgs() throws {
        let result = try Filters.last([], kwargs: [:], env: env)
        #expect(result == .undefined)
    }

    @Test("last filter with empty array")
    func lastFilterEmptyArray() throws {
        let result = try Filters.last([.array([])], kwargs: [:], env: env)
        #expect(result == .undefined)
    }

    @Test("last filter with string")
    func lastFilterString() throws {
        let result = try Filters.last([.string("abc")], kwargs: [:], env: env)
        #expect(result == .string("c"))
    }

    @Test("last filter with empty string")
    func lastFilterEmptyString() throws {
        let result = try Filters.last([.string("")], kwargs: [:], env: env)
        #expect(result == .undefined)
    }

    @Test("last filter with non-array/string throws")
    func lastFilterNonArrayString() throws {
        #expect(throws: JinjaError.self) {
            try Filters.last([.int(42)], kwargs: [:], env: env)
        }
    }

    @Test("random filter with no args")
    func randomFilterNoArgs() throws {
        let result = try Filters.random([], kwargs: [:], env: env)
        #expect(result == .undefined)
    }

    @Test("random filter with array")
    func randomFilterArray() throws {
        let result = try Filters.random([.array([.int(42)])], kwargs: [:], env: env)
        #expect(result == .int(42))
    }

    @Test("random filter with string")
    func randomFilterString() throws {
        let result = try Filters.random([.string("a")], kwargs: [:], env: env)
        #expect(result == .string("a"))
    }

    @Test("random filter with empty string")
    func randomFilterEmptyString() throws {
        let result = try Filters.random([.string("")], kwargs: [:], env: env)
        #expect(result == .undefined)
    }

    @Test("random filter with object")
    func randomFilterObject() throws {
        let result = try Filters.random([.object(["a": .int(1)])], kwargs: [:], env: env)
        #expect(result == .string("a"))
    }

    @Test("random filter with empty object")
    func randomFilterEmptyObject() throws {
        let result = try Filters.random([.object([:])], kwargs: [:], env: env)
        #expect(result == .undefined)
    }

    @Test("random filter with non-iterable")
    func randomFilterNonIterable() throws {
        let result = try Filters.random([.int(42)], kwargs: [:], env: env)
        #expect(result == .undefined)
    }

    @Test("reverse filter with no args")
    func reverseFilterNoArgs() throws {
        let result = try Filters.reverse([], kwargs: [:], env: env)
        #expect(result == .undefined)
    }

    @Test("reverse filter with string")
    func reverseFilterString() throws {
        let result = try Filters.reverse([.string("abc")], kwargs: [:], env: env)
        #expect(result == .string("cba"))
    }

    @Test("reverse filter with non-array/string throws")
    func reverseFilterNonArrayString() throws {
        #expect(throws: JinjaError.self) {
            try Filters.reverse([.int(42)], kwargs: [:], env: env)
        }
    }

    @Test("sort filter with non-array returns empty")
    func sortFilterNonArray() throws {
        let result = try Filters.sort([.int(42)], kwargs: [:], env: env)
        #expect(result == .array([]))
    }

    @Test("sort filter reversed")
    func sortFilterReversed() throws {
        let result = try Filters.sort(
            [.array([.int(1), .int(3), .int(2)]), .boolean(true)],
            kwargs: [:],
            env: env
        )
        #expect(result == .array([.int(3), .int(2), .int(1)]))
    }

    @Test("sort filter with empty attribute")
    func sortFilterEmptyAttribute() throws {
        let result = try Filters.sort(
            [.array([.int(3), .int(1), .int(2)]), .boolean(false), .boolean(false), .string("")],
            kwargs: [:],
            env: env
        )
        #expect(result == .array([.int(1), .int(2), .int(3)]))
    }

    @Test("groupby filter with non-array")
    func groupbyFilterNonArray() throws {
        let result = try Filters.groupby([.int(42), .string("x")], kwargs: [:], env: env)
        #expect(result == .array([]))
    }

    @Test("groupby filter missing attribute throws")
    func groupbyFilterMissingAttribute() throws {
        #expect(throws: JinjaError.self) {
            try Filters.groupby([.array([.int(1)])], kwargs: [:], env: env)
        }
    }

    @Test("groupby filter case sensitive")
    func groupbyFilterCaseSensitive() throws {
        let items: [Value] = [
            .object(["city": .string("NY")]),
            .object(["city": .string("ny")]),
        ]
        let result = try Filters.groupby(
            [.array(items), .string("city")],
            kwargs: ["case_sensitive": .boolean(true)],
            env: env
        )
        guard case let .array(groups) = result else {
            Issue.record("Expected array result")
            return
        }
        #expect(groups.count == 2)
    }

    @Test("slice filter with non-array")
    func sliceFilterNonArray() throws {
        let result = try Filters.slice([.int(42), .int(2)], kwargs: [:], env: env)
        #expect(result == .array([]))
    }

    @Test("slice filter with non-int numSlices throws")
    func sliceFilterNonIntNumSlices() throws {
        #expect(throws: JinjaError.self) {
            try Filters.slice([.array([.int(1)]), .string("x")], kwargs: [:], env: env)
        }
    }

    @Test("slice filter with fill_with")
    func sliceFilterWithFillWith() throws {
        let result = try Filters.slice(
            [.array([.int(1), .int(2), .int(3)]), .int(2), .int(0)],
            kwargs: [:],
            env: env
        )
        guard case let .array(slices) = result else {
            Issue.record("Expected array result")
            return
        }
        #expect(slices.count == 2)
    }

    @Test("map filter with non-array")
    func mapFilterNonArray() throws {
        let result = try Filters.map([.int(42)], kwargs: [:], env: env)
        #expect(result == .array([]))
    }

    @Test("map filter with filterName")
    func mapFilterWithFilterName() throws {
        let items: [Value] = [.string("hello"), .string("world")]
        let result = try Filters.map(
            [.array(items), .string("upper")],
            kwargs: [:],
            env: env
        )
        #expect(result == .array([.string("HELLO"), .string("WORLD")]))
    }

    @Test("map filter with no attribute or filterName")
    func mapFilterNoAttributeOrFilter() throws {
        let result = try Filters.map([.array([.int(1)])], kwargs: [:], env: env)
        #expect(result == .array([]))
    }

    @Test("select filter with non-array")
    func selectFilterNonArray() throws {
        let result = try Filters.select([.int(42)], kwargs: [:], env: env)
        #expect(result == .array([]))
    }

    @Test("select filter with testname")
    func selectFilterWithTestname() throws {
        let items: [Value] = [.int(1), .int(2), .int(3), .int(4)]
        let result = try Filters.select(
            [.array(items), .string("odd")],
            kwargs: [:],
            env: env
        )
        #expect(result == .array([.int(1), .int(3)]))
    }

    @Test("select filter without testname filters by truthiness")
    func selectFilterWithoutTestname() throws {
        let items: [Value] = [.int(0), .int(1), .string(""), .string("hi"), .null]
        let result = try Filters.select([.array(items)], kwargs: [:], env: env)
        #expect(result == .array([.int(1), .string("hi")]))
    }

    @Test("reject filter with non-array")
    func rejectFilterNonArray() throws {
        let result = try Filters.reject([.int(42)], kwargs: [:], env: env)
        #expect(result == .array([]))
    }

    @Test("reject filter with testname")
    func rejectFilterWithTestname() throws {
        let items: [Value] = [.int(1), .int(2), .int(3), .int(4)]
        let result = try Filters.reject(
            [.array(items), .string("odd")],
            kwargs: [:],
            env: env
        )
        #expect(result == .array([.int(2), .int(4)]))
    }

    @Test("reject filter without testname rejects truthy")
    func rejectFilterWithoutTestname() throws {
        let items: [Value] = [.int(0), .int(1), .string(""), .string("hi"), .null]
        let result = try Filters.reject([.array(items)], kwargs: [:], env: env)
        #expect(result == .array([.int(0), .string(""), .null]))
    }

    @Test("selectattr filter with non-array")
    func selectattrFilterNonArray() throws {
        let result = try Filters.selectattr([.int(42), .string("x")], kwargs: [:], env: env)
        #expect(result == .array([]))
    }

    @Test("selectattr filter missing attribute throws")
    func selectattrFilterMissingAttribute() throws {
        #expect(throws: JinjaError.self) {
            try Filters.selectattr([.array([.int(1)])], kwargs: [:], env: env)
        }
    }

    @Test("selectattr filter truthiness mode")
    func selectattrFilterTruthiness() throws {
        let items: [Value] = [
            .object(["active": .boolean(true)]),
            .object(["active": .boolean(false)]),
        ]
        let result = try Filters.selectattr(
            [.array(items), .string("active")],
            kwargs: [:],
            env: env
        )
        #expect(result == .array([items[0]]))
    }

    @Test("rejectattr filter with non-array")
    func rejectattrFilterNonArray() throws {
        let result = try Filters.rejectattr([.int(42), .string("x")], kwargs: [:], env: env)
        #expect(result == .array([]))
    }

    @Test("rejectattr filter missing attribute throws")
    func rejectattrFilterMissingAttribute() throws {
        #expect(throws: JinjaError.self) {
            try Filters.rejectattr([.array([.int(1)])], kwargs: [:], env: env)
        }
    }

    @Test("rejectattr filter truthiness mode")
    func rejectattrFilterTruthiness() throws {
        let items: [Value] = [
            .object(["active": .boolean(true)]),
            .object(["active": .boolean(false)]),
        ]
        let result = try Filters.rejectattr(
            [.array(items), .string("active")],
            kwargs: [:],
            env: env
        )
        #expect(result == .array([items[1]]))
    }

    @Test("rejectattr filter with test")
    func rejectattrFilterWithTest() throws {
        let items: [Value] = [
            .object(["val": .int(2)]),
            .object(["val": .int(3)]),
            .object(["val": .int(4)]),
        ]
        let result = try Filters.rejectattr(
            [.array(items), .string("val"), .string("odd")],
            kwargs: [:],
            env: env
        )
        #expect(result == .array([items[0], items[2]]))
    }

    @Test("attr filter with no args")
    func attrFilterNoArgs() throws {
        let result = try Filters.attr([], kwargs: [:], env: env)
        #expect(result == .undefined)
    }

    @Test("attr filter missing attribute throws")
    func attrFilterMissingAttribute() throws {
        #expect(throws: JinjaError.self) {
            try Filters.attr([.object(["a": .int(1)])], kwargs: [:], env: env)
        }
    }

    @Test("attr filter with attribute")
    func attrFilterWithAttribute() throws {
        let result = try Filters.attr(
            [.object(["name": .string("test")]), .string("name")],
            kwargs: [:],
            env: env
        )
        #expect(result == .string("test"))
    }

    @Test("dictsort filter with non-object")
    func dictsortFilterNonObject() throws {
        let result = try Filters.dictsort([.int(42)], kwargs: [:], env: env)
        #expect(result == .array([]))
    }

    @Test("dictsort filter by value")
    func dictsortFilterByValue() throws {
        let dict = Value.object(["b": .int(1), "a": .int(2)])
        let result = try Filters.dictsort(
            [dict, .boolean(false), .string("value")],
            kwargs: [:],
            env: env
        )
        let expected = Value.array([
            .array([.string("b"), .int(1)]),
            .array([.string("a"), .int(2)]),
        ])
        #expect(result == expected)
    }

    @Test("dictsort filter case sensitive")
    func dictsortFilterCaseSensitive() throws {
        let dict = Value.object(["B": .int(1), "a": .int(2)])
        let result = try Filters.dictsort(
            [dict, .boolean(true)],
            kwargs: [:],
            env: env
        )
        guard case let .array(pairs) = result else {
            Issue.record("Expected array result")
            return
        }
        // Case-sensitive: 'B' < 'a' in ASCII
        if case let .array(first) = pairs[0] {
            #expect(first[0] == .string("B"))
        }
    }

    @Test("forceescape filter with non-string")
    func forceescapeFilterNonString() throws {
        let result = try Filters.forceescape([.int(42)], kwargs: [:], env: env)
        #expect(result == .string(""))
    }

    @Test("safe filter returns input")
    func safeFilterReturnsInput() throws {
        let result = try Filters.safe([.string("<b>bold</b>")], kwargs: [:], env: env)
        #expect(result == .string("<b>bold</b>"))
    }

    @Test("safe filter with no args")
    func safeFilterNoArgs() throws {
        let result = try Filters.safe([], kwargs: [:], env: env)
        #expect(result == .string(""))
    }

    @Test("striptags filter with non-string")
    func striptagsFilterNonString() throws {
        let result = try Filters.striptags([.int(42)], kwargs: [:], env: env)
        #expect(result == .string(""))
    }

    @Test("format filter with %s specifiers")
    func formatFilterWithSpecifiers() throws {
        let result = try Filters.format(
            [.string("Hello %s, you are %s"), .string("world"), .string("great")],
            kwargs: [:],
            env: env
        )
        #expect(result == .string("Hello world, you are great"))
    }

    @Test("format filter with unknown specifier")
    func formatFilterUnknownSpecifier() throws {
        let result = try Filters.format(
            [.string("Value: %d"), .int(42)],
            kwargs: [:],
            env: env
        )
        #expect(result == .string("Value: %d"))
    }

    @Test("format filter with trailing percent")
    func formatFilterTrailingPercent() throws {
        let result = try Filters.format(
            [.string("100%"), .int(1)],
            kwargs: [:],
            env: env
        )
        #expect(result == .string("100%"))
    }

    @Test("format filter with single arg returns input")
    func formatFilterSingleArg() throws {
        let result = try Filters.format([.string("hello")], kwargs: [:], env: env)
        #expect(result == .string("hello"))
    }

    @Test("wordwrap filter with non-string")
    func wordwrapFilterNonString() throws {
        let result = try Filters.wordwrap([.int(42)], kwargs: [:], env: env)
        #expect(result == .string(""))
    }

    @Test("wordwrap filter breaks long words")
    func wordwrapFilterBreaksLongWords() throws {
        let result = try Filters.wordwrap(
            [.string("abcdefghij"), .int(5)],
            kwargs: [:],
            env: env
        )
        if case .string(let str) = result {
            #expect(str.contains("\n"))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("wordwrap filter breaks on hyphens")
    func wordwrapFilterBreaksOnHyphens() throws {
        let result = try Filters.wordwrap(
            [.string("very-long-hyphenated-word"), .int(5)],
            kwargs: [:],
            env: env
        )
        if case .string(let str) = result {
            #expect(str.contains("\n"))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("filesizeformat filter with non-numeric")
    func filesizeformatFilterNonNumeric() throws {
        let result = try Filters.filesizeformat([.string("abc")], kwargs: [:], env: env)
        #expect(result == .string(""))
    }

    @Test("filesizeformat filter with no args")
    func filesizeformatFilterNoArgs() throws {
        let result = try Filters.filesizeformat([], kwargs: [:], env: env)
        #expect(result == .string(""))
    }

    @Test("filesizeformat filter with binary mode")
    func filesizeformatFilterBinary() throws {
        let result = try Filters.filesizeformat(
            [.int(1048576)],
            kwargs: ["binary": .boolean(true)],
            env: env
        )
        if case .string(let str) = result {
            #expect(str.contains("iB"))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("filesizeformat filter with double input")
    func filesizeformatFilterDouble() throws {
        let result = try Filters.filesizeformat([.double(1500.0)], kwargs: [:], env: env)
        if case .string(let str) = result {
            #expect(str.contains("kB") || str.contains("Bytes"))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("filesizeformat filter with small value")
    func filesizeformatFilterSmall() throws {
        let result = try Filters.filesizeformat([.int(500)], kwargs: [:], env: env)
        #expect(result == .string("500 Bytes"))
    }

    @Test("xmlattr filter with non-object")
    func xmlattrFilterNonObject() throws {
        let result = try Filters.xmlattr([.int(42)], kwargs: [:], env: env)
        #expect(result == .string(""))
    }

    @Test("xmlattr filter skips null and undefined")
    func xmlattrFilterSkipsNullUndefined() throws {
        let result = try Filters.xmlattr(
            [.object(["a": .string("1"), "b": .null, "c": .undefined])],
            kwargs: [:],
            env: env
        )
        if case .string(let str) = result {
            #expect(str.contains("a=\"1\""))
            #expect(!str.contains("b="))
            #expect(!str.contains("c="))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("xmlattr filter invalid key throws")
    func xmlattrFilterInvalidKey() throws {
        #expect(throws: JinjaError.self) {
            try Filters.xmlattr([.object(["a b": .string("1")])], kwargs: [:], env: env)
        }
    }

    @Test("xmlattr filter autospace false")
    func xmlattrFilterAutospaceOff() throws {
        let result = try Filters.xmlattr(
            [.object(["a": .string("1")])],
            kwargs: ["autospace": .boolean(false)],
            env: env
        )
        if case .string(let str) = result {
            #expect(!str.hasPrefix(" "))
            #expect(str == "a=\"1\"")
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("string filter with no args")
    func stringFilterNoArgs() throws {
        let result = try Filters.string([], kwargs: [:], env: env)
        #expect(result == .string(""))
    }

    @Test("trim filter with non-string")
    func trimFilterNonString() throws {
        let result = try Filters.trim([.int(42)], kwargs: [:], env: env)
        #expect(result == .string(""))
    }

    @Test("tojson filter with no args")
    func tojsonFilterNoArgs() throws {
        let result = try Filters.tojson([], kwargs: [:], env: env)
        #expect(result == .string("null"))
    }

    @Test("tojson filter with function falls back to null")
    func tojsonFilterFunction() throws {
        let fn = Value.function { _, _, _ in .null }
        let result = try Filters.tojson([fn], kwargs: [:], env: env)
        #expect(result == .string("null"))
    }

    @Test("abs filter with no args")
    func absFilterNoArgs() throws {
        let result = try Filters.abs([], kwargs: [:], env: env)
        #expect(result == .int(0))
    }

    @Test("abs filter with non-numeric throws")
    func absFilterNonNumeric() throws {
        #expect(throws: JinjaError.self) {
            try Filters.abs([.string("abc")], kwargs: [:], env: env)
        }
    }

    @Test("capitalize filter with non-string")
    func capitalizeFilterNonString() throws {
        let result = try Filters.capitalize([.int(42)], kwargs: [:], env: env)
        #expect(result == .string(""))
    }

    @Test("center filter with non-string returns input")
    func centerFilterNonString() throws {
        let result = try Filters.center([.int(42), .int(10)], kwargs: [:], env: env)
        #expect(result == .int(42))
    }

    @Test("center filter missing width throws")
    func centerFilterMissingWidth() throws {
        #expect(throws: JinjaError.self) {
            try Filters.center([.string("hi")], kwargs: [:], env: env)
        }
    }

    @Test("center filter string wider than width")
    func centerFilterStringWiderThanWidth() throws {
        let result = try Filters.center([.string("hello"), .int(3)], kwargs: [:], env: env)
        #expect(result == .string("hello"))
    }

    @Test("float filter with no args")
    func floatFilterNoArgs() throws {
        let result = try Filters.float([], kwargs: [:], env: env)
        #expect(result == .double(0.0))
    }

    @Test("float filter with non-numeric string")
    func floatFilterNonNumericString() throws {
        let result = try Filters.float([.string("abc")], kwargs: [:], env: env)
        #expect(result == .double(0.0))
    }

    @Test("float filter with double passthrough")
    func floatFilterDoublePassthrough() throws {
        let result = try Filters.float([.double(3.14)], kwargs: [:], env: env)
        #expect(result == .double(3.14))
    }

    @Test("float filter with string number")
    func floatFilterStringNumber() throws {
        let result = try Filters.float([.string("3.14")], kwargs: [:], env: env)
        #expect(result == .double(3.14))
    }

    @Test("float filter with non-convertible returns default")
    func floatFilterNonConvertible() throws {
        let result = try Filters.float([.boolean(true)], kwargs: [:], env: env)
        #expect(result == .double(0.0))
    }

    @Test("int filter with no args")
    func intFilterNoArgs() throws {
        let result = try Filters.int([], kwargs: [:], env: env)
        #expect(result == .int(0))
    }

    @Test("int filter with 0b prefix")
    func intFilterBinaryPrefix() throws {
        let result = try Filters.int([.string("0b1010")], kwargs: [:], env: env)
        #expect(result == .int(10))
    }

    @Test("int filter with 0o prefix")
    func intFilterOctalPrefix() throws {
        let result = try Filters.int([.string("0o17")], kwargs: [:], env: env)
        #expect(result == .int(15))
    }

    @Test("int filter with invalid binary")
    func intFilterInvalidBinary() throws {
        let result = try Filters.int([.string("0b999")], kwargs: [:], env: env)
        #expect(result == .int(0))
    }

    @Test("int filter with invalid octal")
    func intFilterInvalidOctal() throws {
        let result = try Filters.int([.string("0o999")], kwargs: [:], env: env)
        #expect(result == .int(0))
    }

    @Test("int filter with invalid hex")
    func intFilterInvalidHex() throws {
        let result = try Filters.int([.string("0xZZZ")], kwargs: [:], env: env)
        #expect(result == .int(0))
    }

    @Test("int filter with non-convertible returns default")
    func intFilterNonConvertible() throws {
        let result = try Filters.int([.boolean(true)], kwargs: [:], env: env)
        #expect(result == .int(0))
    }

    @Test("int filter int passthrough")
    func intFilterIntPassthrough() throws {
        let result = try Filters.int([.int(42)], kwargs: [:], env: env)
        #expect(result == .int(42))
    }

    @Test("int filter non-parseable string returns default")
    func intFilterNonParseableString() throws {
        let result = try Filters.int([.string("abc")], kwargs: [:], env: env)
        #expect(result == .int(0))
    }

    @Test("list filter with no args")
    func listFilterNoArgs() throws {
        let result = try Filters.list([], kwargs: [:], env: env)
        #expect(result == .array([]))
    }

    @Test("list filter with string")
    func listFilterString() throws {
        let result = try Filters.list([.string("abc")], kwargs: [:], env: env)
        #expect(result == .array([.string("a"), .string("b"), .string("c")]))
    }

    @Test("list filter with object")
    func listFilterObject() throws {
        let result = try Filters.list([.object(["a": .int(1), "b": .int(2)])], kwargs: [:], env: env)
        guard case let .array(values) = result else {
            Issue.record("Expected array")
            return
        }
        #expect(values.count == 2)
    }

    @Test("list filter with non-string/array/object")
    func listFilterNonSupported() throws {
        let result = try Filters.list([.int(42)], kwargs: [:], env: env)
        #expect(result == .array([]))
    }

    @Test("max filter with attribute")
    func maxFilterWithAttribute() throws {
        let items: [Value] = [
            .object(["val": .int(1)]),
            .object(["val": .int(3)]),
            .object(["val": .int(2)]),
        ]
        let result = try Filters.max(
            [.array(items)],
            kwargs: ["attribute": .string("val")],
            env: env
        )
        #expect(result == .object(["val": .int(3)]))
    }

    @Test("min filter with attribute")
    func minFilterWithAttribute() throws {
        let items: [Value] = [
            .object(["val": .int(3)]),
            .object(["val": .int(1)]),
            .object(["val": .int(2)]),
        ]
        let result = try Filters.min(
            [.array(items)],
            kwargs: ["attribute": .string("val")],
            env: env
        )
        #expect(result == .object(["val": .int(1)]))
    }

    @Test("max filter comparison error handling")
    func maxFilterComparisonError() throws {
        let items: [Value] = [.int(1), .string("a")]
        let result = try Filters.max([.array(items)], kwargs: [:], env: env)
        // When comparison throws, it returns false, so the first element wins
        #expect(result == .int(1) || result == .string("a"))
    }

    @Test("min filter comparison error handling")
    func minFilterComparisonError() throws {
        let items: [Value] = [.int(1), .string("a")]
        let result = try Filters.min([.array(items)], kwargs: [:], env: env)
        #expect(result == .int(1) || result == .string("a"))
    }

    @Test("round filter with no args")
    func roundFilterNoArgs() throws {
        let result = try Filters.round([], kwargs: [:], env: env)
        #expect(result == .double(0.0))
    }

    @Test("round filter with int input")
    func roundFilterIntInput() throws {
        let result = try Filters.round([.int(3)], kwargs: [:], env: env)
        #expect(result == .double(3.0))
    }

    @Test("round filter with non-numeric returns value")
    func roundFilterNonNumeric() throws {
        let result = try Filters.round([.string("abc")], kwargs: [:], env: env)
        #expect(result == .string("abc"))
    }

    @Test("round filter ceil method")
    func roundFilterCeil() throws {
        let result = try Filters.round(
            [.double(2.3), .int(0), .string("ceil")],
            kwargs: [:],
            env: env
        )
        #expect(result == .double(3.0))
    }

    @Test("round filter floor method")
    func roundFilterFloor() throws {
        let result = try Filters.round(
            [.double(2.7), .int(0), .string("floor")],
            kwargs: [:],
            env: env
        )
        #expect(result == .double(2.0))
    }

    @Test("round filter unknown method")
    func roundFilterUnknownMethod() throws {
        let result = try Filters.round(
            [.double(2.5), .int(0), .string("unknown")],
            kwargs: [:],
            env: env
        )
        #expect(result == .double(2.5))
    }

    @Test("title filter with non-string")
    func titleFilterNonString() throws {
        let result = try Filters.title([.int(42)], kwargs: [:], env: env)
        #expect(result == .string(""))
    }

    @Test("wordcount filter with non-string")
    func wordcountFilterNonString() throws {
        let result = try Filters.wordcount([.int(42)], kwargs: [:], env: env)
        #expect(result == .int(0))
    }

    @Test("replace filter with non-string returns input")
    func replaceFilterNonString() throws {
        let result = try Filters.replace([.int(42), .string("a"), .string("b")], kwargs: [:], env: env)
        #expect(result == .int(42))
    }

    @Test("replace filter with empty old string")
    func replaceFilterEmptyOld() throws {
        let result = try Filters.replace(
            [.string("ab"), .string(""), .string("_")],
            kwargs: [:],
            env: env
        )
        #expect(result == .string("_a_b_"))
    }

    @Test("replace filter with count")
    func replaceFilterWithCount() throws {
        let result = try Filters.replace(
            [.string("aaa"), .string("a"), .string("b"), .int(2)],
            kwargs: [:],
            env: env
        )
        #expect(result == .string("bba"))
    }

    @Test("replace filter with empty old and count")
    func replaceFilterEmptyOldWithCount() throws {
        let result = try Filters.replace(
            [.string("ab"), .string(""), .string("_"), .int(2)],
            kwargs: [:],
            env: env
        )
        #expect(result == .string("_a_b"))
    }

    @Test("urlencode filter with no args")
    func urlencodeFilterNoArgs() throws {
        let result = try Filters.urlencode([], kwargs: [:], env: env)
        #expect(result == .string(""))
    }

    @Test("urlencode filter with non-string/object")
    func urlencodeFilterNonStringObject() throws {
        let result = try Filters.urlencode([.int(42)], kwargs: [:], env: env)
        #expect(result == .string(""))
    }

    @Test("batch filter with non-array")
    func batchFilterNonArray() throws {
        let result = try Filters.batch([.int(42), .int(2)], kwargs: [:], env: env)
        #expect(result == .array([]))
    }

    @Test("batch filter missing batchSize throws")
    func batchFilterMissingBatchSize() throws {
        #expect(throws: JinjaError.self) {
            try Filters.batch([.array([.int(1)]), .string("x")], kwargs: [:], env: env)
        }
    }

    @Test("batch filter with fill_with")
    func batchFilterWithFillWith() throws {
        let result = try Filters.batch(
            [.array([.int(1), .int(2), .int(3)]), .int(2), .int(0)],
            kwargs: [:],
            env: env
        )
        let expected = Value.array([
            .array([.int(1), .int(2)]),
            .array([.int(3), .int(0)]),
        ])
        #expect(result == expected)
    }

    @Test("sum filter with non-array")
    func sumFilterNonArray() throws {
        let result = try Filters.sum([.int(42)], kwargs: [:], env: env)
        #expect(result == .int(0))
    }

    @Test("truncate filter with non-string")
    func truncateFilterNonString() throws {
        let result = try Filters.truncate([.int(42)], kwargs: [:], env: env)
        #expect(result == .string(""))
    }

    @Test("truncate filter killwords")
    func truncateFilterKillwords() throws {
        let result = try Filters.truncate(
            [.string("hello beautiful world"), .int(10), .boolean(true)],
            kwargs: [:],
            env: env
        )
        if case .string(let str) = result {
            #expect(str == "hello beau...")
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("truncate filter word boundary no space")
    func truncateFilterWordBoundaryNoSpace() throws {
        let result = try Filters.truncate(
            [.string("verylongwordwithoutspaces"), .int(10), .boolean(false), .string("..."), .int(0)],
            kwargs: [:],
            env: env
        )
        if case .string(let str) = result {
            #expect(str == "verylongwo...")
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("unique filter case sensitive")
    func uniqueFilterCaseSensitive() throws {
        let values = [Value.string("A"), .string("a")]
        let result = try Filters.unique(
            [.array(values)],
            kwargs: ["case_sensitive": .boolean(true)],
            env: env
        )
        #expect(result == .array([.string("A"), .string("a")]))
    }

    @Test("unique filter non-array")
    func uniqueFilterNonArray() throws {
        let result = try Filters.unique([.int(42)], kwargs: [:], env: env)
        #expect(result == .array([]))
    }

    @Test("indent filter with non-string")
    func indentFilterNonString() throws {
        let result = try Filters.indent([.int(42)], kwargs: [:], env: env)
        #expect(result == .string(""))
    }

    @Test("indent filter with string width")
    func indentFilterStringWidth() throws {
        let result = try Filters.indent(
            [.string("line1\nline2")],
            kwargs: ["width": .string("\t"), "first": .boolean(true)],
            env: env
        )
        if case .string(let str) = result {
            #expect(str.contains("\tline1"))
            #expect(str.contains("\tline2"))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("indent filter with blank lines")
    func indentFilterBlankLines() throws {
        let result = try Filters.indent(
            [.string("line1\n\nline3"), .int(2)],
            kwargs: ["blank": .boolean(true)],
            env: env
        )
        if case .string(let str) = result {
            // blank=true means empty lines are also indented
            let lines = str.split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines[1] == "  ")
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("items filter with no args")
    func itemsFilterNoArgs() throws {
        let result = try Filters.items([], kwargs: [:], env: env)
        #expect(result == .array([]))
    }

    @Test("items filter with non-object")
    func itemsFilterNonObject() throws {
        let result = try Filters.items([.int(42)], kwargs: [:], env: env)
        #expect(result == .array([]))
    }

    @Test("pprint filter with no args")
    func pprintFilterNoArgs() throws {
        let result = try Filters.pprint([], kwargs: [:], env: env)
        #expect(result == .string(""))
    }

    @Test("pprint filter with array")
    func pprintFilterArray() throws {
        let result = try Filters.pprint([.array([.int(1), .int(2)])], kwargs: [:], env: env)
        if case .string(let str) = result {
            #expect(str.contains("["))
            #expect(str.contains("]"))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("pprint filter with empty array")
    func pprintFilterEmptyArray() throws {
        let result = try Filters.pprint([.array([])], kwargs: [:], env: env)
        #expect(result == .string("[]"))
    }

    @Test("pprint filter with empty object")
    func pprintFilterEmptyObject() throws {
        let result = try Filters.pprint([.object([:])], kwargs: [:], env: env)
        #expect(result == .string("{}"))
    }

    @Test("pprint filter with string")
    func pprintFilterString() throws {
        let result = try Filters.pprint([.string("hello")], kwargs: [:], env: env)
        #expect(result == .string("\"hello\""))
    }

    @Test("pprint filter with number")
    func pprintFilterNumber() throws {
        let result = try Filters.pprint([.int(42)], kwargs: [:], env: env)
        #expect(result == .string("42"))
    }

    @Test("urlize filter with non-string")
    func urlizeFilterNonString() throws {
        let result = try Filters.urlize([.int(42)], kwargs: [:], env: env)
        #expect(result == .string(""))
    }

    @Test("urlize filter with trim_url_limit")
    func urlizeFilterTrimUrlLimit() throws {
        let result = try Filters.urlize(
            [.string("Visit https://very-long-example.com/path/to/page")],
            kwargs: ["trim_url_limit": .int(10)],
            env: env
        )
        if case .string(let str) = result {
            #expect(str.contains("..."))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("urlize filter with nofollow")
    func urlizeFilterNofollow() throws {
        let result = try Filters.urlize(
            [.string("https://example.com")],
            kwargs: ["nofollow": .boolean(true)],
            env: env
        )
        if case .string(let str) = result {
            #expect(str.contains("rel=\"nofollow\""))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("urlize filter with target")
    func urlizeFilterTarget() throws {
        let result = try Filters.urlize(
            [.string("https://example.com")],
            kwargs: ["target": .string("_blank")],
            env: env
        )
        if case .string(let str) = result {
            #expect(str.contains("target=\"_blank\""))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("urlize filter with rel")
    func urlizeFilterRel() throws {
        let result = try Filters.urlize(
            [.string("https://example.com")],
            kwargs: ["rel": .string("noopener")],
            env: env
        )
        if case .string(let str) = result {
            #expect(str.contains("rel=\"noopener\""))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("urlize filter with www prefix")
    func urlizeFilterWww() throws {
        let result = try Filters.urlize([.string("www.example.com")], kwargs: [:], env: env)
        if case .string(let str) = result {
            #expect(str.contains("href=\"https://www.example.com\""))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("urlize filter with trailing text")
    func urlizeFilterTrailingText() throws {
        let result = try Filters.urlize(
            [.string("Go to https://example.com now!")],
            kwargs: [:],
            env: env
        )
        if case .string(let str) = result {
            #expect(str.contains("now!"))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("urlize filter with leading punctuation")
    func urlizeFilterLeadingPunctuation() throws {
        let result = try Filters.urlize(
            [.string("(https://example.com)")],
            kwargs: [:],
            env: env
        )
        if case .string(let str) = result {
            #expect(str.contains("("))
            #expect(str.contains(")"))
            #expect(str.contains("href=\"https://example.com\""))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("escape alias e")
    func escapeAliasE() throws {
        guard let fn = Filters.builtIn["e"] else {
            Issue.record("Expected escape alias 'e' to be registered")
            return
        }
        let result = try fn([.string("<b>hi</b>")], [:], env)
        if case .string(let str) = result {
            #expect(str.contains("&lt;"))
            #expect(str.contains("&gt;"))
        } else {
            Issue.record("Expected string result")
        }
    }

    @Test("count alias for length")
    func countAliasForLength() throws {
        guard let fn = Filters.builtIn["count"] else {
            Issue.record("Expected count alias to be registered")
            return
        }
        let result = try fn([.array([.int(1), .int(2)])], [:], env)
        #expect(result == .int(2))
    }
}
