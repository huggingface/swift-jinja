import Foundation
import Testing

@testable import Jinja

@Suite("JSON Tests")
struct JSONTests {
    // Expected strings below are what Python's `json.dumps` produces
    // for the same input and keyword arguments.

    @Test("dumps writes a space after commas and colons")
    func dumpsDefaultSeparators() throws {
        let value: Value = ["b": 1, "a": [1, 2.5, true, nil, "x"]]
        #expect(try JSON.dumps(value) == #"{"b": 1, "a": [1, 2.5, true, null, "x"]}"#)
    }

    @Test("dumps preserves insertion order")
    func dumpsPreservesInsertionOrder() throws {
        let value: Value = ["z": 1, "a": 2, "m": 3]
        #expect(try JSON.dumps(value) == #"{"z": 1, "a": 2, "m": 3}"#)
    }

    @Test("dumps sorts keys when asked")
    func dumpsSortKeys() throws {
        let value: Value = ["z": 1, "a": ["y": 1, "b": 2], "m": 3]
        #expect(
            try JSON.dumps(value, options: .init(sortKeys: true))
                == #"{"a": {"b": 2, "y": 1}, "m": 3, "z": 1}"#
        )
    }

    @Test("dumps escapes non-ASCII by default")
    func dumpsEnsureASCIIDefault() throws {
        #expect(try JSON.dumps(.string("— 🏳️")) == "\"\\u2014 \\ud83c\\udff3\\ufe0f\"")
    }

    @Test("dumps keeps non-ASCII with ensure_ascii false")
    func dumpsEnsureASCIIFalse() throws {
        #expect(try JSON.dumps(.string("— 🏳️"), options: .init(ensureASCII: false)) == #""— 🏳️""#)
    }

    @Test("dumps escapes quotes, backslashes, and control characters but not slashes")
    func dumpsStringEscapes() throws {
        let input = Value.string("a\"b\\c/d\n\t\u{01}\u{7F}")
        #expect(try JSON.dumps(input) == "\"a\\\"b\\\\c/d\\n\\t\\u0001\\u007f\"")
        // With ensure_ascii off, only quotes, backslashes, and C0 controls are escaped.
        #expect(
            try JSON.dumps(input, options: .init(ensureASCII: false))
                == "\"a\\\"b\\\\c/d\\n\\t\\u0001\u{7F}\""
        )
    }

    @Test("dumps indents like json.dumps")
    func dumpsIndent() throws {
        let value: Value = ["a": [1, 2], "b": [:], "c": []]
        #expect(
            try JSON.dumps(value, options: .init(indent: 2))
                == """
                {
                  "a": [
                    1,
                    2
                  ],
                  "b": {},
                  "c": []
                }
                """
        )
    }

    @Test("dumps honors custom separators")
    func dumpsSeparators() throws {
        let value: Value = ["a": [1, 2]]
        #expect(
            try JSON.dumps(value, options: .init(separators: (",", ":")))
                == #"{"a":[1,2]}"#
        )
    }

    @Test("dumps formats numbers like Python")
    func dumpsNumbers() throws {
        #expect(try JSON.dumps(.double(1.0)) == "1.0")
        #expect(try JSON.dumps(.double(0.1)) == "0.1")
        #expect(try JSON.dumps(.double(-2.5)) == "-2.5")
        #expect(try JSON.dumps(.double(1e15)) == "1000000000000000.0")
        #expect(try JSON.dumps(.double(1e16)) == "1e+16")
        #expect(try JSON.dumps(.double(0.0001)) == "0.0001")
        #expect(try JSON.dumps(.double(0.00001)) == "1e-05")
        #expect(try JSON.dumps(.double(123456.789)) == "123456.789")
        #expect(try JSON.dumps(.double(0.000123)) == "0.000123")
        #expect(try JSON.dumps(.double(1.5e-7)) == "1.5e-07")
        #expect(try JSON.dumps(.double(1e22)) == "1e+22")
        #expect(try JSON.dumps(.double(12_345_678_901_234_567_890.0)) == "1.2345678901234567e+19")
        #expect(try JSON.dumps(.int(-42)) == "-42")
        #expect(try JSON.dumps(.double(.nan)) == "NaN")
        #expect(try JSON.dumps(.double(.infinity)) == "Infinity")
        #expect(try JSON.dumps(.double(-.infinity)) == "-Infinity")
    }

    @Test("dumps writes integer keys as strings")
    func dumpsIntegerKeys() throws {
        let value = Value.object([.int(1): .string("one"), .string("two"): .int(2)])
        #expect(try JSON.dumps(value) == #"{"1": "one", "two": 2}"#)
    }

    @Test("dumps rejects values that are not JSON serializable")
    func dumpsRejectsFunctions() throws {
        let value = Value.function { _, _, _ in .null }
        #expect(throws: JinjaError.self) {
            try JSON.dumps(value)
        }
    }

    @Test("dumps rejects undefined values at any depth")
    func dumpsRejectsUndefined() throws {
        let values: [Value] = [.undefined, [.undefined], ["key": .undefined], ["key": [1, .undefined]]]
        for value in values {
            #expect(throws: JinjaError.self) {
                try JSON.dumps(value)
            }
        }
        #expect(try JSON.dumps(.null) == "null")
    }

    @Test("dumps sorts integer keys numerically before stringifying them")
    func dumpsSortsIntegerKeys() throws {
        let value = Value.object([.int(10): .string("ten"), .int(2): .string("two")])
        #expect(
            try JSON.dumps(value, options: .init(sortKeys: true))
                == #"{"2": "two", "10": "ten"}"#
        )
    }

    @Test("dumps rejects mixed key types only when sorting")
    func dumpsMixedKeys() throws {
        let value = Value.object([.int(2): .string("two"), .string("a"): .int(1)])
        #expect(try JSON.dumps(value) == #"{"2": "two", "a": 1}"#)
        #expect(throws: JinjaError.self) {
            try JSON.dumps(value, options: .init(sortKeys: true))
        }
    }

    @Test("dumps sorts string keys by Unicode scalar order like Python")
    func dumpsSortsUnicodeKeys() throws {
        let value: Value = ["é": 1, "z": 2, "e\u{301}x": 3]
        #expect(
            try JSON.dumps(value, options: .init(ensureASCII: false, sortKeys: true))
                == "{\"e\u{301}x\": 3, \"z\": 2, \"é\": 1}"
        )
    }

    @Test("dumps treats negative indentation as zero through all option paths")
    func dumpsNegativeIndent() throws {
        let value: Value = [[1]]
        let expected = "[\n[\n1\n]\n]"
        #expect(try JSON.dumps(value, options: .init(indent: -1)) == expected)
        var options = JSON.DumpsOptions(indent: 2)
        options.indent = Int.min
        #expect(try JSON.dumps(value, options: options) == expected)
        #expect(try JSON.dumps(value, options: .init(indent: 0)) == expected)
    }

    @Test("htmlSafeDumps escapes HTML-significant characters like Jinja2")
    func htmlSafeDumps() throws {
        #expect(
            try JSON.htmlSafeDumps(.string("<script>&'\"</script>"))
                == "\"\\u003cscript\\u003e\\u0026\\u0027\\\"\\u003c/script\\u003e\""
        )
    }
}
