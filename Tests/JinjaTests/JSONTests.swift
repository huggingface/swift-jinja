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

    @Test("dumps options can be read from a kwargs object")
    func dumpsOptionsFromKwargs() throws {
        let options = try JSON.DumpsOptions(
            kwargs: [
                "ensure_ascii": false,
                "sort_keys": true,
                "indent": 4,
                "separators": [",", ": "],
            ]
        )
        #expect(options.ensureASCII == false)
        #expect(options.sortKeys == true)
        #expect(options.indent == 4)
        #expect(options.separators?.item == ",")
        #expect(options.separators?.key == ": ")
    }

    @Test("dumps options reject unknown kwargs")
    func dumpsOptionsRejectUnknownKwargs() throws {
        #expect(throws: JinjaError.self) {
            try JSON.DumpsOptions(kwargs: ["allow_nan": false])
        }
    }

    @Test("htmlSafeDumps escapes HTML-significant characters like Jinja2")
    func htmlSafeDumps() throws {
        #expect(
            try JSON.htmlSafeDumps(.string("<script>&'\"</script>"))
                == "\"\\u003cscript\\u003e\\u0026\\u0027\\\"\\u003c/script\\u003e\""
        )
    }
}
