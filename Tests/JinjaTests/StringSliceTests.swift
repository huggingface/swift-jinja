import Testing

@testable import Jinja

/// Slicing a string selects characters (extended grapheme clusters)
/// with the same bounds and steps as slicing a list.
/// For strings where each character is one Unicode scalar,
/// the expected results match Python.
@Suite("String slices")
struct StringSliceTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let string: String
        let slice: String
        let expected: String
        var testDescription: String { "\(string.debugDescription)[\(slice)]" }
    }

    static let cases: [Case] = [
        // ASCII
        Case(string: "abcdef", slice: "1:4", expected: "bcd"),
        Case(string: "abcdef", slice: "-2:", expected: "ef"),
        Case(string: "abcdef", slice: ":-2", expected: "abcd"),
        Case(string: "abcdef", slice: "::2", expected: "ace"),
        Case(string: "abcdef", slice: "1::2", expected: "bdf"),
        Case(string: "abcdef", slice: "::-1", expected: "fedcba"),
        Case(string: "abcdef", slice: "4:1:-1", expected: "edc"),
        Case(string: "abcdef", slice: "-1:-4:-2", expected: "fd"),
        Case(string: "abcdef", slice: "2:100", expected: "cdef"),
        Case(string: "abcdef", slice: "-100:2", expected: "ab"),
        Case(string: "abcdef", slice: "100:", expected: ""),
        Case(string: "abcdef", slice: "4:1", expected: ""),
        Case(string: "abcdef", slice: "1:4:-1", expected: ""),
        Case(string: "abcdef", slice: "::-100", expected: "f"),
        Case(string: "abcdef", slice: "100::-1", expected: "fedcba"),
        Case(string: "abcdef", slice: "-100::-1", expected: ""),
        // Multi-byte UTF-8
        Case(string: "héllo wörld", slice: "1:5", expected: "éllo"),
        Case(string: "héllo wörld", slice: "::-1", expected: "dlröw olléh"),
        Case(string: "héllo wörld", slice: "-5:", expected: "wörld"),
        Case(string: "héllo wörld", slice: "::3", expected: "hlwl"),
        Case(string: "héllo wörld", slice: "7:1:-2", expected: "ö l"),
        // Characters with several Unicode scalars
        Case(string: "👨‍👩‍👧e\u{301}🇺🇸日本", slice: "1:3", expected: "e\u{301}🇺🇸"),
        Case(string: "👨‍👩‍👧e\u{301}🇺🇸日本", slice: "::-1", expected: "本日🇺🇸e\u{301}👨‍👩‍👧"),
        Case(string: "👨‍👩‍👧e\u{301}🇺🇸日本", slice: "::2", expected: "👨‍👩‍👧🇺🇸本"),
        Case(string: "👨‍👩‍👧e\u{301}🇺🇸日本", slice: "-2:", expected: "日本"),
        Case(string: "👨‍👩‍👧e\u{301}🇺🇸日本", slice: "-10:1", expected: "👨‍👩‍👧"),
        Case(string: "👨‍👩‍👧e\u{301}🇺🇸日本", slice: "3:10", expected: "日本"),
        Case(string: "a\r\nb\rc", slice: "1:3", expected: "\r\nb"),
        Case(string: "a\r\nb\rc", slice: "::-1", expected: "c\rb\r\na"),
        Case(string: "a\r\nb\rc", slice: "::2", expected: "abc"),
    ]

    @Test(arguments: cases)
    func slice(_ c: Case) throws {
        let rendered = try Template("{{ s[\(c.slice)] }}").render(["s": .string(c.string)])
        #expect(rendered == c.expected)
    }

    /// Slicing a string gives the same characters as
    /// slicing the list of its characters,
    /// for every combination of bounds and steps,
    /// including bounds before the start and after the end.
    @Test(arguments: ["", "abcdef", "héllo wörld", "👨‍👩‍👧e\u{301}🇺🇸日本", "a\r\nb\rc"])
    func matchesListSlice(_ string: String) throws {
        let bounds = ["", "-10", "-3", "-1", "0", "1", "3", "10"]
        let steps = ["", "1", "2", "3", "-1", "-2", "-3"]
        var expressions: [String] = []
        for start in bounds {
            for stop in bounds {
                for step in steps {
                    expressions.append(step.isEmpty ? "\(start):\(stop)" : "\(start):\(stop):\(step)")
                }
            }
        }

        // Render every slice in one template, separated by a character
        // that isn't in any of the strings.
        let stringSlices = expressions.map { "{{ s[\($0)] }}" }.joined(separator: "|")
        let listSlices = expressions.map { "{{ (s | list)[\($0)] | join }}" }.joined(separator: "|")
        let context: [String: Value] = ["s": .string(string)]
        let actual = try Template(stringSlices).render(context).split(separator: "|", omittingEmptySubsequences: false)
        let expected = try Template(listSlices).render(context).split(separator: "|", omittingEmptySubsequences: false)

        #expect(actual.count == expressions.count)
        for (expression, (actual, expected)) in zip(expressions, zip(actual, expected)) {
            #expect(actual == expected, "s[\(expression)]")
        }
    }
}
