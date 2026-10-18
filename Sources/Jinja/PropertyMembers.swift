import Foundation
@_exported import OrderedCollections

/// Property member access handlers for different value types.
///
/// This provides dot-notation property access functionality for various value types,
/// such as string methods (`str.upper()`), object properties, and built-in methods.
public enum PropertyMembers {
    /// Evaluates property member access on a value.
    ///
    /// - Parameters:
    ///   - object: The object to access the property on
    ///   - propertyName: The name of the property to access
    /// - Returns: The property value or `.undefined` if not found
    /// - Throws: `JinjaError.runtime` for invalid operations
    public static func evaluate(_ object: Value, _ propertyName: String) throws -> Value {
        switch object {
        case let .string(str):
            return try evaluateStringProperty(str, propertyName)
        case let .object(obj):
            return try evaluateObjectProperty(obj, propertyName)
        default:
            return .undefined
        }
    }

    // MARK: - String Properties

    private static func evaluateStringProperty(_ str: String, _ propertyName: String) throws
        -> Value
    {
        switch propertyName {
        case "upper":
            return .function { args, kwargs, _ in
                _ = try resolveCallArguments(args: args, kwargs: kwargs, parameters: [])
                return .string(str.uppercased())
            }
        case "lower":
            return .function { args, kwargs, _ in
                _ = try resolveCallArguments(args: args, kwargs: kwargs, parameters: [])
                return .string(str.lowercased())
            }
        case "title":
            return .function { args, kwargs, _ in
                _ = try resolveCallArguments(args: args, kwargs: kwargs, parameters: [])
                return .string(str.capitalized)
            }
        case "strip":
            return .function { args, kwargs, _ in
                guard args.count <= 1 else {
                    throw JinjaError.runtime(
                        "strip() takes at most 1 argument (\(args.count) given)"
                    )
                }
                let arguments = try resolveCallArguments(
                    args: args,
                    kwargs: kwargs,
                    parameters: ["chars"],
                    defaults: ["chars": .null]
                )
                let characterSet: CharacterSet
                switch arguments["chars"] {
                case let .string(chars):
                    characterSet = CharacterSet(charactersIn: chars)
                case .null, .none:
                    characterSet = .whitespacesAndNewlines
                default:
                    throw JinjaError.runtime(
                        "strip() chars argument must be a string or null"
                    )
                }
                return .string(str.trimmingCharacters(in: characterSet))
            }
        case "lstrip":
            return .function { args, kwargs, _ in
                guard args.count <= 1 else {
                    throw JinjaError.runtime(
                        "lstrip() takes at most 1 argument (\(args.count) given)"
                    )
                }
                let arguments = try resolveCallArguments(
                    args: args,
                    kwargs: kwargs,
                    parameters: ["chars"],
                    defaults: ["chars": .null]
                )
                let characterSet: CharacterSet
                switch arguments["chars"] {
                case let .string(chars):
                    characterSet = CharacterSet(charactersIn: chars)
                case .null, .none:
                    characterSet = .whitespacesAndNewlines
                default:
                    throw JinjaError.runtime(
                        "lstrip() chars argument must be a string or null"
                    )
                }
                return .string(
                    String(
                        String.UnicodeScalarView(
                            str.unicodeScalars.drop(while: characterSet.contains)
                        )
                    )
                )
            }
        case "rstrip":
            return .function { args, kwargs, _ in
                guard args.count <= 1 else {
                    throw JinjaError.runtime(
                        "rstrip() takes at most 1 argument (\(args.count) given)"
                    )
                }
                let arguments = try resolveCallArguments(
                    args: args,
                    kwargs: kwargs,
                    parameters: ["chars"],
                    defaults: ["chars": .null]
                )
                let characterSet: CharacterSet
                switch arguments["chars"] {
                case let .string(chars):
                    characterSet = CharacterSet(charactersIn: chars)
                case .null, .none:
                    characterSet = .whitespacesAndNewlines
                default:
                    throw JinjaError.runtime(
                        "rstrip() chars argument must be a string or null"
                    )
                }
                return .string(
                    String(
                        String.UnicodeScalarView(
                            str.unicodeScalars.reversed().drop(while: characterSet.contains)
                                .reversed()
                        )
                    )
                )
            }
        case "split":
            return .function { args, kwargs, _ in
                let arguments = try resolveCallArguments(
                    args: args,
                    kwargs: kwargs,
                    parameters: ["separator", "maxsplit"],
                    defaults: ["separator": .null, "maxsplit": .int(-1)]
                )

                let separator: String? = {
                    guard case let .string(sep) = arguments["separator"] else { return nil }
                    return sep
                }()

                let limit: Int? = {
                    guard case let .int(maxsplit) = arguments["maxsplit"], maxsplit >= 0 else {
                        return nil
                    }
                    return maxsplit
                }()

                let components = split(string: str, separator: separator, limit: limit)
                return .array(components.map(Value.string))
            }
        case "replace":
            return .function { args, kwargs, _ in
                let arguments = try resolveCallArguments(
                    args: args,
                    kwargs: kwargs,
                    parameters: ["old", "new", "count"],
                    defaults: ["count": .int(-1)]
                )

                guard case let .string(old) = arguments["old"],
                    case let .string(new) = arguments["new"]
                else {
                    throw JinjaError.runtime("replace() requires 'old' and 'new' string arguments")
                }

                let maxReplacements: Int? = {
                    guard case let .int(count) = arguments["count"], count >= 0 else { return nil }
                    return count
                }()

                let result = replace(
                    string: str,
                    old: old,
                    new: new,
                    maxReplacements: maxReplacements
                )
                return .string(result)
            }
        case "startswith":
            return .function { args, kwargs, _ in
                let arguments = try resolveCallArguments(
                    args: args,
                    kwargs: kwargs,
                    parameters: ["prefix"]
                )

                guard case let .string(prefix) = arguments["prefix"] else {
                    throw JinjaError.runtime("startswith() requires a string prefix")
                }
                return .boolean(str.hasPrefix(prefix))
            }
        case "endswith":
            return .function { args, kwargs, _ in
                let arguments = try resolveCallArguments(
                    args: args,
                    kwargs: kwargs,
                    parameters: ["suffix"]
                )

                guard case let .string(suffix) = arguments["suffix"] else {
                    throw JinjaError.runtime("endswith() requires a string suffix")
                }
                return .boolean(str.hasSuffix(suffix))
            }
        case "format":
            return .function { args, kwargs, _ in
                let result = try pythonFormat(string: str, args: args, kwargs: kwargs)
                return .string(result)
            }
        case "join":
            return .function { args, kwargs, _ in
                guard kwargs.isEmpty else {
                    throw JinjaError.runtime("join() takes no keyword arguments")
                }
                guard args.count == 1 else {
                    throw JinjaError.runtime(
                        "join() takes exactly one argument (\(args.count) given)"
                    )
                }

                let items: [Value]
                switch args[0] {
                case let .array(array):
                    items = array
                case let .string(string):
                    items = string.unicodeScalars.map { .string(String($0)) }
                case let .object(object):
                    items = object.keys.map(Value.init)
                case .undefined:
                    items = []
                default:
                    throw JinjaError.runtime("join() can only join an iterable")
                }

                let strings = try items.enumerated().map { index, item in
                    guard case let .string(string) = item else {
                        throw JinjaError.runtime(
                            "join() sequence item \(index): expected a string"
                        )
                    }
                    return string
                }
                return .string(strings.joined(separator: str))
            }
        default:
            return .undefined
        }
    }

    // MARK: - Object Properties

    private static func evaluateObjectProperty(
        _ obj: OrderedDictionary<ObjectKey, Value>,
        _ propertyName: String
    ) throws -> Value {
        switch propertyName {
        case "items":
            let fn: @Sendable ([Value], [String: Value], Environment) throws -> Value = {
                args,
                kwargs,
                _ in
                _ = try resolveCallArguments(args: args, kwargs: kwargs, parameters: [])
                let pairs = obj.map { key, value in Value.array([Value(key), value]) }
                return .array(pairs)
            }
            return .function(fn)
        case "get":
            let fn: @Sendable ([Value], [String: Value], Environment) throws -> Value = {
                args,
                kwargs,
                _ in
                let arguments = try resolveCallArguments(
                    args: args,
                    kwargs: kwargs,
                    parameters: ["key", "default"],
                    defaults: ["default": .null]
                )

                guard let keyValue = arguments["key"] else {
                    throw JinjaError.runtime("get() requires a 'key' argument")
                }

                let defaultValue = arguments["default"] ?? .null
                guard let key = ObjectKey(keyValue) else {
                    return defaultValue
                }
                return obj[key] ?? defaultValue
            }
            return .function(fn)
        case "keys":
            let fn: @Sendable ([Value], [String: Value], Environment) throws -> Value = {
                args,
                kwargs,
                _ in
                _ = try resolveCallArguments(args: args, kwargs: kwargs, parameters: [])
                let keys = obj.keys.map(Value.init)
                return .array(keys)
            }
            return .function(fn)
        case "values":
            let fn: @Sendable ([Value], [String: Value], Environment) throws -> Value = {
                args,
                kwargs,
                _ in
                _ = try resolveCallArguments(args: args, kwargs: kwargs, parameters: [])
                return .array(Array(obj.values))
            }
            return .function(fn)
        default:
            return obj[.string(propertyName)] ?? .undefined
        }
    }
}

// MARK: - Private Helper Functions

/// Splits a string using a separator and optional limit.
/// - Parameters:
///   - string: The string to split
///   - separator: The separator to split on (nil for whitespace)
///   - limit: Maximum number of splits to perform (nil for unlimited)
/// - Returns: Array of string components
private func split(string: String, separator: String?, limit: Int?) -> [String] {
    if let separator = separator {
        if let limit = limit {
            // Split with limit: split at most 'limit' times
            var components: [String] = []
            var remaining = string
            var splits = 0

            while splits < limit, let range = remaining.range(of: separator) {
                components.append(String(remaining[..<range.lowerBound]))
                remaining = String(remaining[range.upperBound...])
                splits += 1
            }
            // Add the remainder
            components.append(remaining)
            return components
        } else {
            return string.components(separatedBy: separator)
        }
    } else {
        // Split on whitespace
        return string.split(separator: " ").map(String.init)
    }
}

/// Formats a string the way Python's `str.format` does.
///
/// Supports automatic (`{}`), positional (`{0}`), and keyword (`{name}`) fields,
/// the `!s` and `!r` conversions, and the `{{` and `}}` escapes.
/// Throws for format specs, other conversions, and attribute or item access in fields,
/// rather than rendering them differently from Python.
/// - Parameters:
///   - string: The format string
///   - args: The positional arguments
///   - kwargs: The keyword arguments
/// - Returns: The formatted string
private func pythonFormat(string: String, args: [Value], kwargs: [String: Value]) throws -> String {
    let scalars = Array(string.unicodeScalars)
    var result = String.UnicodeScalarView()
    var automaticIndex = 0
    var usesAutomaticNumbering = false
    var usesManualNumbering = false
    var index = 0

    while index < scalars.count {
        let scalar = scalars[index]
        let next = index + 1 < scalars.count ? scalars[index + 1] : nil

        if scalar == "}" {
            guard next == "}" else {
                throw JinjaError.runtime("Single '}' encountered in format string")
            }
            result.append("}")
            index += 2
            continue
        }
        guard scalar == "{" else {
            result.append(scalar)
            index += 1
            continue
        }
        if next == "{" {
            result.append("{")
            index += 2
            continue
        }

        // Find the closing brace, allowing for nested fields in a format spec.
        var end = index + 1
        var depth = 1
        while end < scalars.count {
            if scalars[end] == "{" {
                depth += 1
            } else if scalars[end] == "}" {
                depth -= 1
                if depth == 0 { break }
            }
            end += 1
        }
        guard end < scalars.count else {
            throw JinjaError.runtime("expected '}' before end of string")
        }
        let field = String(String.UnicodeScalarView(scalars[(index + 1) ..< end]))
        index = end + 1

        // Split the field into its name, conversion, and format spec.
        let nameEnd = field.firstIndex { $0 == "!" || $0 == ":" } ?? field.endIndex
        let name = field[..<nameEnd]
        guard !name.contains("."), !name.contains("[") else {
            throw JinjaError.runtime(
                "format() doesn't support attribute or item access in field '{\(field)}'"
            )
        }
        var conversion: Character?
        var rest = field[nameEnd...]
        if rest.first == "!" {
            rest = rest.dropFirst()
            guard let character = rest.first else {
                throw JinjaError.runtime("format() field '{\(field)}' is missing a conversion")
            }
            conversion = character
            rest = rest.dropFirst()
            guard rest.isEmpty || rest.first == ":" else {
                throw JinjaError.runtime("expected ':' after conversion specifier")
            }
        }
        let spec = rest.dropFirst()
        guard spec.isEmpty else {
            throw JinjaError.runtime("format() doesn't support the format spec ':\(spec)'")
        }

        // Look up the value for the field.
        let value: Value
        if name.isEmpty {
            guard !usesManualNumbering else {
                throw JinjaError.runtime(
                    "cannot switch from manual field specification to automatic field numbering"
                )
            }
            usesAutomaticNumbering = true
            guard automaticIndex < args.count else {
                throw JinjaError.runtime(
                    "Replacement index \(automaticIndex) out of range for positional args tuple"
                )
            }
            value = args[automaticIndex]
            automaticIndex += 1
        } else if name.allSatisfy({ $0.isASCII && $0.isNumber }) {
            guard !usesAutomaticNumbering else {
                throw JinjaError.runtime(
                    "cannot switch from automatic field numbering to manual field specification"
                )
            }
            usesManualNumbering = true
            guard let position = Int(name), position < args.count else {
                throw JinjaError.runtime(
                    "Replacement index \(name) out of range for positional args tuple"
                )
            }
            value = args[position]
        } else {
            guard let keywordValue = kwargs[String(name)] else {
                throw JinjaError.runtime("format() is missing keyword argument '\(name)'")
            }
            value = keywordValue
        }

        // Python would show a function's memory address, which can't match.
        if case .function = value {
            throw JinjaError.runtime("format() can't convert a function to a string")
        }

        switch conversion {
        case nil, "s":
            result.append(contentsOf: pythonStr(value).unicodeScalars)
        case "r":
            result.append(contentsOf: value.pythonRepr.unicodeScalars)
        case let conversion?:
            throw JinjaError.runtime("format() doesn't support the conversion '!\(conversion)'")
        }
    }

    return String(result)
}

/// Returns the string form of a value as Python's `str()` gives it.
///
/// An undefined value is an empty string, as in Jinja2.
/// - Parameter value: The value to convert
/// - Returns: The string form of the value
private func pythonStr(_ value: Value) -> String {
    switch value {
    case let .string(string):
        return string
    case .undefined:
        return ""
    default:
        return value.pythonRepr
    }
}

/// Replaces occurrences of old string with new string, optionally limiting replacements.
/// - Parameters:
///   - string: The string to perform replacements on
///   - old: The substring to replace
///   - new: The replacement string
///   - maxReplacements: Maximum number of replacements (nil for unlimited)
/// - Returns: The string with replacements made
private func replace(string: String, old: String, new: String, maxReplacements: Int?)
    -> String
{
    // Special case: replacing empty string inserts at character boundaries
    if old.isEmpty {
        var result = ""
        var replacements = 0
        for char in string {
            if let count = maxReplacements, replacements >= count {
                result += String(char)
            } else {
                result += new + String(char)
                replacements += 1
            }
        }
        // Add final replacement if we haven't hit the count limit
        if maxReplacements == nil || replacements < maxReplacements! {
            result += new
        }
        return result
    }

    if let count = maxReplacements {
        // Replace only the first 'count' occurrences
        var result = string
        var replacements = 0
        while replacements < count, let range = result.range(of: old) {
            result.replaceSubrange(range, with: new)
            replacements += 1
        }
        return result
    } else {
        return string.replacingOccurrences(of: old, with: new)
    }
}
