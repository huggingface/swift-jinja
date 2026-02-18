import Foundation
import Testing

@testable import Jinja

@Suite("Globals Tests")
struct GlobalsTests {
    let env = Environment()

    @Test("raise_exception without arguments")
    func raiseException() throws {
        #expect(throws: TemplateException.self) {
            try Globals.raiseException([], [:], env)
        }
    }

    @Test("raise_exception with custom message")
    func raiseExceptionWithMessage() throws {
        do {
            try Globals.raiseException(["Template error: invalid input"], [:], env)
        } catch let error as TemplateException {
            #expect(error.message == "Template error: invalid input")
        }
    }

    @Test("strftime_now with basic format")
    func strftimeNowBasic() throws {
        let result = try Globals.strftimeNow([.string("%Y-%m-%d")], [:], env)
        guard case let .string(dateString) = result else {
            #expect(Bool(false), "Expected string result")
            return
        }

        // Verify the result matches the expected format (YYYY-MM-DD)
        let regex = try NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}$")
        let range = NSRange(location: 0, length: dateString.utf16.count)
        let matches = regex.firstMatch(in: dateString, range: range)
        #expect(matches != nil, "Date string should match YYYY-MM-DD format")
    }

    @Test("strftime_now with time format")
    func strftimeNowTime() throws {
        let result = try Globals.strftimeNow([.string("%H:%M:%S")], [:], env)
        guard case let .string(timeString) = result else {
            #expect(Bool(false), "Expected string result")
            return
        }

        // Verify the result matches the expected format (HH:MM:SS)
        let regex = try NSRegularExpression(pattern: "^\\d{2}:\\d{2}:\\d{2}$")
        let range = NSRange(location: 0, length: timeString.utf16.count)
        let matches = regex.firstMatch(in: timeString, range: range)
        #expect(matches != nil, "Time string should match HH:MM:SS format")
    }

    @Test("strftime_now with weekday format")
    func strftimeNowWeekday() throws {
        let result = try Globals.strftimeNow([.string("%A")], [:], env)
        guard case let .string(weekdayString) = result else {
            #expect(Bool(false), "Expected string result")
            return
        }

        // Verify the result is a valid weekday name
        let weekdays = [
            "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
        ]
        #expect(weekdays.contains(weekdayString), "Result should be a valid weekday name")
    }

    @Test("strftime_now with complex format")
    func strftimeNowComplex() throws {
        let result = try Globals.strftimeNow([.string("%A, %B %d, %Y at %I:%M %p")], [:], env)
        guard case let .string(dateString) = result else {
            #expect(Bool(false), "Expected string result")
            return
        }

        // Should contain expected components
        #expect(dateString.contains(", "), "Should contain day/month separator")
        #expect(dateString.contains(" at "), "Should contain date/time separator")
        #expect(dateString.contains("AM") || dateString.contains("PM"), "Should contain AM/PM")

        // Check basic structure - should look like "Monday, September 15, 2025 at 01:30 PM"
        let regex = try NSRegularExpression(
            pattern: "\\w+, \\w+ \\d{1,2}, \\d{4} at \\d{1,2}:\\d{2} (AM|PM)"
        )
        let range = NSRange(location: 0, length: dateString.utf16.count)
        let matches = regex.firstMatch(in: dateString, range: range)
        #expect(
            matches != nil,
            "Complex date format should match expected pattern, got: \(dateString)"
        )
    }

    @Test("strftime_now with literal percent")
    func strftimeNowLiteralPercent() throws {
        let result = try Globals.strftimeNow([.string("%%Y")], [:], env)
        guard case let .string(resultString) = result else {
            #expect(Bool(false), "Expected string result")
            return
        }

        #expect(resultString == "%Y", "Should handle literal percent correctly")
    }

    @Test("strftime_now with no arguments")
    func strftimeNowNoArguments() throws {
        #expect(throws: JinjaError.self) {
            try Globals.strftimeNow([], [:], env)
        }
    }

    @Test("strftime_now with too many arguments")
    func strftimeNowTooManyArguments() throws {
        #expect(throws: JinjaError.self) {
            try Globals.strftimeNow([.string("%Y"), .string("%m")], [:], env)
        }
    }

    @Test("strftime_now with non-string argument")
    func strftimeNowNonStringArgument() throws {
        #expect(throws: JinjaError.self) {
            try Globals.strftimeNow([.int(2024)], [:], env)
        }
    }

    // MARK: - range

    @Test("range with 1 argument")
    func rangeOneArg() throws {
        let result = try Globals.range([.int(5)], [:], env)
        #expect(result == .array([.int(0), .int(1), .int(2), .int(3), .int(4)]))
    }

    @Test("range with 2 arguments")
    func rangeTwoArgs() throws {
        let result = try Globals.range([.int(2), .int(5)], [:], env)
        #expect(result == .array([.int(2), .int(3), .int(4)]))
    }

    @Test("range with 3 arguments")
    func rangeThreeArgs() throws {
        let result = try Globals.range([.int(0), .int(10), .int(3)], [:], env)
        #expect(result == .array([.int(0), .int(3), .int(6), .int(9)]))
    }

    @Test("range with negative step")
    func rangeNegativeStep() throws {
        let result = try Globals.range([.int(5), .int(0), .int(-1)], [:], env)
        #expect(result == .array([.int(5), .int(4), .int(3), .int(2), .int(1)]))
    }

    @Test("range with zero step throws")
    func rangeZeroStep() throws {
        #expect(throws: JinjaError.self) {
            try Globals.range([.int(0), .int(5), .int(0)], [:], env)
        }
    }

    @Test("range with wrong argument count throws")
    func rangeWrongArgCount() throws {
        #expect(throws: JinjaError.self) {
            try Globals.range([], [:], env)
        }
        #expect(throws: JinjaError.self) {
            try Globals.range([.int(1), .int(2), .int(3), .int(4)], [:], env)
        }
    }

    @Test("range with non-integer argument throws")
    func rangeNonIntArg() throws {
        #expect(throws: JinjaError.self) {
            try Globals.range([.string("5")], [:], env)
        }
    }

    // MARK: - dict

    @Test("dict creates object from kwargs")
    func dictFromKwargs() throws {
        let result = try Globals.dict([], ["a": .int(1), "b": .int(2)], env)
        guard case let .object(obj) = result else {
            #expect(Bool(false), "Expected object result")
            return
        }
        #expect(obj["a"] == .int(1))
        #expect(obj["b"] == .int(2))
    }

    // MARK: - cycler

    @Test("cycler cycles through values")
    func cyclerCycles() throws {
        let result = try Globals.cycler([.string("a"), .string("b")], [:], env)
        guard case let .object(obj) = result else {
            #expect(Bool(false), "Expected object result")
            return
        }

        #expect(obj["current"] == .string("a"))

        guard case let .function(nextFn) = obj["next"] else {
            #expect(Bool(false), "Expected next to be a function")
            return
        }

        let first = try nextFn([], [:], env)
        #expect(first == .string("a"))

        let second = try nextFn([], [:], env)
        #expect(second == .string("b"))

        let third = try nextFn([], [:], env)
        #expect(third == .string("a"))
    }

    @Test("cycler with no arguments throws")
    func cyclerEmpty() throws {
        #expect(throws: JinjaError.self) {
            try Globals.cycler([], [:], env)
        }
    }

    // MARK: - joiner

    @Test("joiner returns empty then separator")
    func joinerBehavior() throws {
        let result = try Globals.joiner([], [:], env)
        guard case let .function(joinFn) = result else {
            #expect(Bool(false), "Expected function result")
            return
        }

        let first = try joinFn([], [:], env)
        #expect(first == .string(""))

        let second = try joinFn([], [:], env)
        #expect(second == .string(", "))

        let third = try joinFn([], [:], env)
        #expect(third == .string(", "))
    }

    // MARK: - namespace

    @Test("namespace creates object from kwargs")
    func namespaceFromKwargs() throws {
        let result = try Globals.namespace([], ["x": .int(1)], env)
        guard case let .object(obj) = result else {
            #expect(Bool(false), "Expected object result")
            return
        }
        #expect(obj["x"] == .int(1))
    }

    // MARK: - lipsum

    @Test("lipsum without HTML")
    func lipsumNoHtml() throws {
        let result = try Globals.lipsum([], ["html": .boolean(false), "n": .int(2)], env)
        guard case let .string(text) = result else {
            #expect(Bool(false), "Expected string result")
            return
        }
        #expect(!text.contains("<p>"))
        #expect(!text.contains("</p>"))
        #expect(text.contains("\n\n"), "Paragraphs should be separated by double newlines")
    }

    @Test("lipsum with single paragraph")
    func lipsumSingleParagraph() throws {
        let result = try Globals.lipsum([], ["n": .int(1), "html": .boolean(true)], env)
        guard case let .string(text) = result else {
            #expect(Bool(false), "Expected string result")
            return
        }
        #expect(text.hasPrefix("<p>"))
        #expect(text.hasSuffix("</p>"))
        #expect(!text.contains("\n"), "Single paragraph should have no newlines")
    }

    // MARK: - range error paths

    @Test("range with non-integer 2-arg throws")
    func rangeNonInteger2Arg() throws {
        #expect(throws: JinjaError.self) {
            try Globals.range([.string("x"), .int(5)], [:], env)
        }
    }

    @Test("range with non-integer 3-arg throws")
    func rangeNonInteger3Arg() throws {
        #expect(throws: JinjaError.self) {
            try Globals.range([.int(0), .string("x"), .int(1)], [:], env)
        }
    }

    // MARK: - lipsum error paths

    @Test("lipsum with invalid args throws")
    func lipsumInvalidArgs() throws {
        #expect(throws: JinjaError.self) {
            try Globals.lipsum([], ["n": .string("x"), "html": .boolean(true)], env)
        }
    }

    // MARK: - strftime_now edge cases

    @Test("strftime_now with unknown format code")
    func strftimeNowUnknownFormatCode() throws {
        let result = try Globals.strftimeNow([.string("%Q")], [:], env)
        guard case let .string(str) = result else {
            #expect(Bool(false), "Expected string result")
            return
        }
        #expect(str == "%Q")
    }

    @Test("strftime_now with trailing percent")
    func strftimeNowTrailingPercent() throws {
        let result = try Globals.strftimeNow([.string("hello%")], [:], env)
        guard case let .string(str) = result else {
            #expect(Bool(false), "Expected string result")
            return
        }
        #expect(str == "hello%")
    }

    // MARK: - cycler reset

    @Test("cycler reset")
    func cyclerReset() throws {
        let result = try Globals.cycler([.string("a"), .string("b"), .string("c")], [:], env)
        guard case let .object(obj) = result else {
            #expect(Bool(false), "Expected object result")
            return
        }

        guard case let .function(nextFn) = obj["next"],
            case let .function(resetFn) = obj["reset"]
        else {
            #expect(Bool(false), "Expected next and reset functions")
            return
        }

        let first = try nextFn([], [:], env)
        #expect(first == .string("a"))

        let second = try nextFn([], [:], env)
        #expect(second == .string("b"))

        _ = try resetFn([], [:], env)

        let afterReset = try nextFn([], [:], env)
        #expect(afterReset == .string("a"))
    }
}
