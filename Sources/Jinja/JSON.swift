import Foundation

/// JSON serialization with the semantics of Python's `json.dumps`.
///
/// Jinja2's `tojson` filter and the `json.dumps` call that transformers
/// substitutes for it both produce this format,
/// so templates written against either render the same text here.
public enum JSON {
    /// Keyword arguments for ``dumps(_:options:)``,
    /// named after the `json.dumps` parameters they correspond to.
    public struct DumpsOptions: Sendable {
        /// Escape every non-ASCII character as `\uXXXX`.
        /// The default is `true`, as in `json.dumps`.
        public var ensureASCII: Bool

        /// Write object keys in sorted order instead of insertion order.
        public var sortKeys: Bool

        /// Number of spaces to indent nested values by.
        /// `nil` writes everything on one line.
        /// Zero or negative values insert newlines without leading spaces.
        public var indent: Int?

        /// The separators written between items and between a key and its value.
        /// `nil` selects `json.dumps`' defaults:
        /// `", "` and `": "`, or `","` and `": "` when indenting.
        public var separators: (item: String, key: String)?

        public init(
            ensureASCII: Bool = true,
            sortKeys: Bool = false,
            indent: Int? = nil,
            separators: (item: String, key: String)? = nil
        ) {
            self.ensureASCII = ensureASCII
            self.sortKeys = sortKeys
            self.indent = indent
            self.separators = separators
        }
    }

    /// The serializer used by the `tojson` filter.
    public enum Serializer: Sendable {
        /// Python's `json.dumps` formatting without HTML escaping.
        case standard
        /// JSON with `<`, `>`, `&`, and `'` escaped for embedding in HTML.
        case htmlSafe
        /// A custom serializer receiving the value and resolved options.
        case custom(@Sendable (Value, DumpsOptions) throws -> String)

        /// Serializes a value using the selected behavior.
        public func dumps(_ value: Value, options: DumpsOptions = DumpsOptions()) throws -> String {
            switch self {
            case .standard:
                return try JSON.dumps(value, options: options)
            case .htmlSafe:
                return try JSON.htmlSafeDumps(value, options: options)
            case .custom(let serialize):
                return try serialize(value, options)
            }
        }
    }

    /// Serializes a value the way `json.dumps` does.
    ///
    /// - Throws: `JinjaError.runtime` when the value contains something
    ///   that has no JSON representation, such as an undefined value or a function.
    public static func dumps(_ value: Value, options: DumpsOptions = DumpsOptions()) throws -> String {
        var writer = Writer(options: options)
        try writer.write(value, depth: 0)
        return writer.output
    }

    /// Serializes a value the way Jinja2's `tojson` filter does:
    /// ``dumps(_:options:)`` with `<`, `>`, `&`, and `'` written as `\u` escapes,
    /// so the result is safe to embed in HTML.
    public static func htmlSafeDumps(_ value: Value, options: DumpsOptions = DumpsOptions()) throws
        -> String
    {
        try dumps(value, options: options)
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "&", with: "\\u0026")
            .replacingOccurrences(of: "'", with: "\\u0027")
    }
}

// MARK: -

extension JSON {
    private struct Writer {
        let options: DumpsOptions
        let itemSeparator: String
        let keySeparator: String
        var output = ""

        init(options: DumpsOptions) {
            self.options = options
            if let separators = options.separators {
                itemSeparator = separators.item
                keySeparator = separators.key
            } else {
                itemSeparator = options.indent == nil ? ", " : ","
                keySeparator = ": "
            }
        }

        mutating func write(_ value: Value, depth: Int) throws {
            switch value {
            case .null:
                output += "null"
            case .undefined:
                throw JinjaError.runtime("Object of type Undefined is not JSON serializable")
            case let .boolean(flag):
                output += flag ? "true" : "false"
            case let .int(number):
                output += String(number)
            case let .double(number):
                output += pythonRepr(number)
            case let .string(string):
                writeString(string)
            case let .array(items):
                guard !items.isEmpty else {
                    output += "[]"
                    return
                }
                output += "["
                for (index, item) in items.enumerated() {
                    if index > 0 { output += itemSeparator }
                    newline(depth: depth + 1)
                    try write(item, depth: depth + 1)
                }
                newline(depth: depth)
                output += "]"
            case let .object(members):
                guard !members.isEmpty else {
                    output += "{}"
                    return
                }
                var entries = Array(members)
                if options.sortKeys {
                    try entries.sort {
                        switch ($0.key, $1.key) {
                        case let (.int(lhs), .int(rhs)):
                            return lhs < rhs
                        case let (.string(lhs), .string(rhs)):
                            return lhs.unicodeScalars.lexicographicallyPrecedes(rhs.unicodeScalars)
                        default:
                            throw JinjaError.runtime("json.dumps cannot sort mixed integer and string keys")
                        }
                    }
                }
                output += "{"
                for (index, entry) in entries.enumerated() {
                    if index > 0 { output += itemSeparator }
                    newline(depth: depth + 1)
                    writeString(entry.key.stringValue)
                    output += keySeparator
                    try write(entry.value, depth: depth + 1)
                }
                newline(depth: depth)
                output += "}"
            case .function:
                throw JinjaError.runtime("Object of type function is not JSON serializable")
            case .macro:
                throw JinjaError.runtime("Object of type macro is not JSON serializable")
            }
        }

        private mutating func newline(depth: Int) {
            guard let indent = options.indent else { return }
            output += "\n"
            output += String(repeating: " ", count: Swift.max(0, indent) * depth)
        }

        private mutating func writeString(_ string: String) {
            output += "\""
            for scalar in string.unicodeScalars {
                switch scalar {
                case "\"": output += "\\\""
                case "\\": output += "\\\\"
                case "\n": output += "\\n"
                case "\r": output += "\\r"
                case "\t": output += "\\t"
                case "\u{08}": output += "\\b"
                case "\u{0C}": output += "\\f"
                default:
                    let isControl = scalar.value < 0x20
                    let isNonASCII = scalar.value > 0x7E
                    if isControl || (options.ensureASCII && isNonASCII) {
                        for unit in String(scalar).utf16 {
                            output += String(format: "\\u%04x", unit)
                        }
                    } else {
                        output.unicodeScalars.append(scalar)
                    }
                }
            }
            output += "\""
        }
    }

    /// Formats a double the way Python's `float.__repr__` does:
    /// the shortest digits that round-trip,
    /// positional for exponents from -4 up to 15,
    /// and exponential with a signed two-digit exponent otherwise.
    private static func pythonRepr(_ number: Double) -> String {
        if number.isNaN { return "NaN" }
        if number.isInfinite { return number < 0 ? "-Infinity" : "Infinity" }
        if number == 0 { return number.sign == .minus ? "-0.0" : "0.0" }

        // Swift's description already gives the shortest round-trip digits;
        // pull them apart and lay them out again by Python's rules.
        let description = String(number.magnitude)
        let parts = description.split(separator: "e", maxSplits: 1)
        let mantissa = parts[0]
        let exponent = parts.count > 1 ? Int(parts[1]) ?? 0 : 0

        let pointIndex = mantissa.firstIndex(of: ".") ?? mantissa.endIndex
        let integerLength = mantissa.distance(from: mantissa.startIndex, to: pointIndex)
        let digits = Array(mantissa.filter { $0 != "." })
        let firstSignificant = digits.firstIndex { $0 != "0" } ?? 0
        var significant = Array(digits[firstSignificant...])
        while significant.count > 1, significant.last == "0" { significant.removeLast() }
        let decimalExponent = integerLength - 1 - firstSignificant + exponent

        var result = number < 0 ? "-" : ""
        if decimalExponent >= -4 && decimalExponent < 16 {
            if decimalExponent >= 0 {
                let integerCount = decimalExponent + 1
                let padded =
                    significant
                    + Array(repeating: Character("0"), count: Swift.max(0, integerCount - significant.count))
                result += String(padded[..<integerCount])
                let fraction = padded[integerCount...]
                result += "." + (fraction.isEmpty ? "0" : String(fraction))
            } else {
                result += "0." + String(repeating: "0", count: -decimalExponent - 1) + String(significant)
            }
        } else {
            result += String(significant[0])
            if significant.count > 1 {
                result += "." + String(significant[1...])
            }
            result += "e" + (decimalExponent < 0 ? "-" : "+")
            result += String(format: "%02d", Swift.abs(decimalExponent))
        }
        return result
    }
}
