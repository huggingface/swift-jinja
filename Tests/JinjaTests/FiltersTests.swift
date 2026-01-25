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
}
