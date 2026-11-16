/// Resolves positional and keyword arguments, mimicking Python's argument handling.
///
/// This function takes the arguments passed to a filter and resolves them against a list of
/// parameter names and a dictionary of default values. It ensures that arguments are not
/// passed both positionally and by keyword, and that all required arguments are present.
///
/// Based on the argument passing conventions in Jinja's Python implementation.
/// See: https://github.com/pallets/jinja/blob/main/src/jinja2/filters.py
///
/// - Parameters:
///   - args: An array of positional arguments (`Value`).
///   - kwargs: A dictionary of keyword arguments (`[String: Value]`).
///   - parameters: An ordered list of parameter names for the filter.
///   - defaults: A dictionary of default values for optional parameters.
/// - Returns: A dictionary of resolved argument names and their `Value`.
/// - Throws: `JinjaError.runtime` if arguments are invalid (e.g., duplicate, unexpected).
internal func resolveCallArguments(
    args: [Value],
    kwargs: [String: Value],
    parameters: [String],
    defaults: [String: Value] = [:]
) throws -> [String: Value] {
    var resolvedArgs: [String: Value] = [:]

    // Handle positional arguments
    for (i, arg) in args.enumerated() {
        if i >= parameters.count {
            break  // Allow for filters with variable arguments
        }
        let paramName = parameters[i]
        if kwargs.keys.contains(paramName) {
            throw JinjaError.runtime(
                "Argument '\(paramName)' passed both positionally and as keyword."
            )
        }
        resolvedArgs[paramName] = arg
    }

    // Handle keyword arguments
    for (name, value) in kwargs {
        guard parameters.contains(name) else {
            throw JinjaError.runtime("Unexpected keyword argument '\(name)' for filter.")
        }
        // This check is technically redundant if the positional loop is correct,
        // but it's a good safeguard.
        if resolvedArgs[name] != nil {
            throw JinjaError.runtime("Argument '\(name)' passed both positionally and as keyword.")
        }
        resolvedArgs[name] = value
    }

    // Apply defaults and check for missing required arguments
    for paramName in parameters {
        if resolvedArgs[paramName] == nil {
            if let defaultValue = defaults[paramName] {
                resolvedArgs[paramName] = defaultValue
            } else {
                // This is a required argument that wasn't provided
                throw JinjaError.runtime("Missing required argument '\(paramName)' for filter.")
            }
        }
    }

    return resolvedArgs
}

/// Returns the value of an `Int` operation, or throws if the operation overflowed.
///
/// Python integers have arbitrary precision, so Jinja2 doesn't overflow.
/// swift-jinja has no arbitrary-precision integers,
/// so it throws instead of trapping.
///
/// - Parameters:
///   - result: The result of an operation such as `addingReportingOverflow(_:)`.
///   - expression: A description of the operation for the error message.
/// - Returns: The result of the operation.
/// - Throws: `JinjaError.runtime` if the operation overflowed.
internal func checkedInt(
    _ result: (partialValue: Int, overflow: Bool),
    _ expression: @autoclosure () -> String
) throws -> Int {
    guard !result.overflow else {
        throw JinjaError.runtime("Integer overflow in \(expression())")
    }
    return result.partialValue
}

/// The most bytes that a template can allocate at once by repeating one value,
/// as in `'-' * 80`, the padding of `center` and `batch`,
/// the indentation of `indent` and `tojson`, or the list of slices that `slice` makes.
///
/// Jinja2 has no such limit:
/// Python raises `MemoryError` when an allocation fails,
/// but Swift stops the process.
/// So swift-jinja throws before it makes one of these allocations larger than this.
/// The limit applies to each allocation, not to the total memory that a template uses.
/// 256 MiB is far more than a chat template renders
/// (a prompt of one million tokens is about 4 MB of text)
/// and far less than the gigabytes that would exhaust the memory of a phone.
internal let maximumRepetitionSize = 1 << 28

/// Returns a string repeated `count` times, as Python's `str * int` does.
///
/// A count of zero or less gives an empty string.
///
/// - Parameters:
///   - string: The string to repeat.
///   - count: The number of times to repeat it.
/// - Returns: The repeated string.
/// - Throws: `JinjaError.runtime` if the result would be larger than
///   ``maximumRepetitionSize`` bytes of UTF-8.
internal func repeatedString(_ string: String, count: Int) throws -> String {
    guard count > 0, !string.isEmpty else { return "" }
    let (size, overflow) = string.utf8.count.multipliedReportingOverflow(by: count)
    guard !overflow, size <= maximumRepetitionSize else {
        throw JinjaError.runtime(
            "Repeating a string \(count) times exceeds the limit of \(maximumRepetitionSize) bytes"
        )
    }
    return String(repeating: string, count: count)
}

/// Returns an array of an element repeated `count` times, as Python's `list * int` does.
///
/// A count of zero or less gives an empty array.
///
/// - Parameters:
///   - element: The element to repeat.
///   - count: The number of times to repeat it.
/// - Returns: The array of repeated elements.
/// - Throws: `JinjaError.runtime` if the array's storage would be larger than
///   ``maximumRepetitionSize`` bytes.
internal func repeatedArray<Element>(_ element: Element, count: Int) throws -> [Element] {
    guard count > 0 else { return [] }
    let (size, overflow) = MemoryLayout<Element>.stride.multipliedReportingOverflow(by: count)
    guard !overflow, size <= maximumRepetitionSize else {
        throw JinjaError.runtime(
            "Repeating a value \(count) times exceeds the limit of \(maximumRepetitionSize) bytes"
        )
    }
    return Array(repeating: element, count: count)
}

/// Converts a double to an integer, rounding toward zero as Python's `int()` does.
///
/// - Parameter value: The double to convert.
/// - Returns: The integer part of the double.
/// - Throws: `JinjaError.runtime` if the double is infinite, NaN,
///   or outside the range of `Int`.
internal func truncatedInt(_ value: Double) throws -> Int {
    guard let int = Int(exactly: value.rounded(.towardZero)) else {
        throw JinjaError.runtime("Cannot convert \(value) to an integer")
    }
    return int
}

extension Unicode.Scalar {
    /// Whether Python's `str.isspace()` is true for this scalar:
    /// Unicode's `White_Space` property and the separators U+001C through U+001F.
    var isPythonWhitespace: Bool {
        properties.isWhitespace || (0x1C ... 0x1F).contains(value)
    }
}

/// Splits a string into lines as Python's `str.splitlines()` does.
///
/// The line boundaries are `\n`, `\r`, `\r\n`, `\v`, `\f`, U+001C through U+001E,
/// U+0085, U+2028, and U+2029.
/// The result has no empty last line for a string that ends with a boundary.
internal func pythonSplitLines(_ string: String) -> [String] {
    var lines: [String] = []
    var line = String.UnicodeScalarView()
    var scalars = string.unicodeScalars.makeIterator()
    var pending = scalars.next()
    while let scalar = pending {
        pending = scalars.next()
        switch scalar.value {
        case 0x0D:
            if pending == "\n" { pending = scalars.next() }
            fallthrough
        case 0x0A, 0x0B, 0x0C, 0x1C, 0x1D, 0x1E, 0x85, 0x2028, 0x2029:
            lines.append(String(line))
            line = String.UnicodeScalarView()
        default:
            line.append(scalar)
        }
    }
    if !line.isEmpty { lines.append(String(line)) }
    return lines
}

/// Decodes HTML character references as Python's `html.unescape()` does.
///
/// It decodes named references from the HTML5 table, with or without a semicolon,
/// and decimal and hexadecimal references,
/// replacing the code points that HTML5 forbids as Python does.
internal func htmlUnescape(_ string: String) -> String {
    guard string.contains("&") else { return string }
    let scalars = Array(string.unicodeScalars)
    var result = String.UnicodeScalarView()
    var index = 0

    func isDigit(_ scalar: Unicode.Scalar, radix: Int) -> Bool {
        Int(String(scalar), radix: radix) != nil
    }

    while index < scalars.count {
        guard scalars[index] == "&", index + 1 < scalars.count else {
            result.append(scalars[index])
            index += 1
            continue
        }
        var end = index + 1
        if scalars[end] == "#" {
            // `#[0-9]+;?` or `#[xX][0-9a-fA-F]+;?`
            var radix = 10
            var digitsStart = end + 1
            if digitsStart < scalars.count, scalars[digitsStart] == "x" || scalars[digitsStart] == "X" {
                radix = 16
                digitsStart += 1
            }
            end = digitsStart
            while end < scalars.count, isDigit(scalars[end], radix: radix) { end += 1 }
            guard end > digitsStart else {
                result.append(scalars[index])
                index += 1
                continue
            }
            let digits = String(String.UnicodeScalarView(scalars[digitsStart ..< end]))
            if end < scalars.count, scalars[end] == ";" { end += 1 }
            result.append(contentsOf: decodedCharacterReference(Int(digits, radix: radix)).unicodeScalars)
            index = end
            continue
        }
        // `[^\t\n\f <&#;]{1,32};?`
        while end < scalars.count, end - index - 1 < 32, !"\t\n\u{0C} <&#;".unicodeScalars.contains(scalars[end]) {
            end += 1
        }
        guard end > index + 1 else {
            result.append(scalars[index])
            index += 1
            continue
        }
        if end < scalars.count, scalars[end] == ";" { end += 1 }
        let name = Array(scalars[(index + 1) ..< end])
        result.append(contentsOf: decodedNamedReference(name).unicodeScalars)
        index = end
    }
    return String(result)
}

/// Decodes a numeric character reference; `nil` is a number too large for `Int`.
private func decodedCharacterReference(_ number: Int?) -> String {
    let replacements: [Int: String] = [
        0x00: "\u{FFFD}", 0x0D: "\r", 0x80: "\u{20AC}", 0x81: "\u{81}", 0x82: "\u{201A}",
        0x83: "\u{192}", 0x84: "\u{201E}", 0x85: "\u{2026}", 0x86: "\u{2020}", 0x87: "\u{2021}",
        0x88: "\u{2C6}", 0x89: "\u{2030}", 0x8A: "\u{160}", 0x8B: "\u{2039}", 0x8C: "\u{152}",
        0x8D: "\u{8D}", 0x8E: "\u{17D}", 0x8F: "\u{8F}", 0x90: "\u{90}", 0x91: "\u{2018}",
        0x92: "\u{2019}", 0x93: "\u{201C}", 0x94: "\u{201D}", 0x95: "\u{2022}", 0x96: "\u{2013}",
        0x97: "\u{2014}", 0x98: "\u{2DC}", 0x99: "\u{2122}", 0x9A: "\u{161}", 0x9B: "\u{203A}",
        0x9C: "\u{153}", 0x9D: "\u{9D}", 0x9E: "\u{17E}", 0x9F: "\u{178}",
    ]
    guard let number, number <= 0x10FFFF else { return "\u{FFFD}" }
    if let replacement = replacements[number] { return replacement }
    guard let scalar = Unicode.Scalar(number) else { return "\u{FFFD}" }  // surrogates
    let value = scalar.value
    let isInvalid =
        (0x01 ... 0x08).contains(value) || (0x0E ... 0x1F).contains(value)
        || (0x7F ... 0x9F).contains(value) || (0xFDD0 ... 0xFDEF).contains(value)
        || value == 0x0B || value & 0xFFFE == 0xFFFE
    return isInvalid ? "" : String(scalar)
}

/// Decodes a named character reference, or the longest name that begins it.
private func decodedNamedReference(_ name: [Unicode.Scalar]) -> String {
    let text = String(String.UnicodeScalarView(name))
    if let value = htmlEntities[text] { return value }
    // Python tries each shorter prefix, down to two characters.
    var length = name.count - 1
    while length > 1 {
        let prefix = String(String.UnicodeScalarView(name[..<length]))
        if let value = htmlEntities[prefix] {
            return value + String(String.UnicodeScalarView(name[length...]))
        }
        length -= 1
    }
    return "&" + text
}
