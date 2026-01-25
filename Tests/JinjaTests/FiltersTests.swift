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

    @Test("unique filter")
    func uniqueFilter() throws {
        let values = [Value.int(1), .int(2), .int(1), .int(3), .int(2)]
        let result = try Filters.unique([.array(values)], kwargs: [:], env: env)
        let expected = Value.array([.int(1), .int(2), .int(3)])
        #expect(result == expected)
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
