// A JSON parser that keeps object key order and the difference between integers and floats.
//
// Foundation's JSON decoders lose key order,
// which changes the output of `tojson` and of loops over dictionaries.
// Tests/JinjaTests/OrderedJSON.swift is a copy of this file.

import Jinja
import OrderedCollections

struct OrderedJSONError: Error, CustomStringConvertible {
    let description: String
}

func parseOrderedJSON(_ text: String) throws -> Value {
    var parser = OrderedJSONParser(text)
    let value = try parser.parseValue()
    parser.skipWhitespace()
    guard parser.index == parser.scalars.count else {
        throw OrderedJSONError(description: "trailing characters at \(parser.index)")
    }
    return value
}

private struct OrderedJSONParser {
    let scalars: [Unicode.Scalar]
    var index = 0

    init(_ text: String) {
        scalars = Array(text.unicodeScalars)
    }

    mutating func skipWhitespace() {
        while index < scalars.count, [" ", "\n", "\r", "\t"].contains(scalars[index]) {
            index += 1
        }
    }

    func peek() throws -> Unicode.Scalar {
        guard index < scalars.count else {
            throw OrderedJSONError(description: "unexpected end of input")
        }
        return scalars[index]
    }

    mutating func next() throws -> Unicode.Scalar {
        let scalar = try peek()
        index += 1
        return scalar
    }

    mutating func expect(_ text: String) throws {
        for scalar in text.unicodeScalars {
            guard try next() == scalar else {
                throw OrderedJSONError(description: "expected \(text) at \(index)")
            }
        }
    }

    mutating func parseValue() throws -> Value {
        skipWhitespace()
        switch try peek() {
        case "{":
            return try parseObject()
        case "[":
            return try parseArray()
        case "\"":
            return .string(try parseString())
        case "t":
            try expect("true")
            return .boolean(true)
        case "f":
            try expect("false")
            return .boolean(false)
        case "n":
            try expect("null")
            return .null
        default:
            return try parseNumber()
        }
    }

    mutating func parseObject() throws -> Value {
        try expect("{")
        var object = OrderedDictionary<ObjectKey, Value>()
        skipWhitespace()
        if try peek() == "}" {
            index += 1
            return .object(object)
        }
        while true {
            skipWhitespace()
            let key = try parseString()
            skipWhitespace()
            try expect(":")
            object[.string(key)] = try parseValue()
            skipWhitespace()
            switch try next() {
            case ",":
                continue
            case "}":
                return .object(object)
            default:
                throw OrderedJSONError(description: "expected , or } at \(index)")
            }
        }
    }

    mutating func parseArray() throws -> Value {
        try expect("[")
        var array: [Value] = []
        skipWhitespace()
        if try peek() == "]" {
            index += 1
            return .array(array)
        }
        while true {
            array.append(try parseValue())
            skipWhitespace()
            switch try next() {
            case ",":
                continue
            case "]":
                return .array(array)
            default:
                throw OrderedJSONError(description: "expected , or ] at \(index)")
            }
        }
    }

    mutating func parseString() throws -> String {
        try expect("\"")
        var result = String.UnicodeScalarView()
        while true {
            let scalar = try next()
            switch scalar {
            case "\"":
                return String(result)
            case "\\":
                switch try next() {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "b": result.append("\u{8}")
                case "f": result.append("\u{C}")
                case "/": result.append("/")
                case "\\": result.append("\\")
                case "\"": result.append("\"")
                case "u":
                    var code = try parseHex4()
                    if (0xD800 ..< 0xDC00).contains(code), index + 1 < scalars.count,
                        scalars[index] == "\\", scalars[index + 1] == "u"
                    {
                        index += 2
                        let low = try parseHex4()
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    }
                    result.append(Unicode.Scalar(code) ?? "\u{FFFD}")
                default:
                    throw OrderedJSONError(description: "bad escape at \(index)")
                }
            default:
                result.append(scalar)
            }
        }
    }

    mutating func parseHex4() throws -> UInt32 {
        var text = ""
        for _ in 0 ..< 4 {
            text.unicodeScalars.append(try next())
        }
        guard let value = UInt32(text, radix: 16) else {
            throw OrderedJSONError(description: "bad \\u escape at \(index)")
        }
        return value
    }

    mutating func parseNumber() throws -> Value {
        let start = index
        var isFloat = false
        while index < scalars.count, "+-0123456789.eE".unicodeScalars.contains(scalars[index]) {
            if ".eE".unicodeScalars.contains(scalars[index]) {
                isFloat = true
            }
            index += 1
        }
        let text = String(String.UnicodeScalarView(scalars[start ..< index]))
        if !isFloat, let integer = Int(text) {
            return .int(integer)
        }
        guard let double = Double(text) else {
            throw OrderedJSONError(description: "bad number \(text) at \(start)")
        }
        return .double(double)
    }
}
