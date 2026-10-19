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

/// The most bytes that a template can allocate by repeating one value,
/// as in `'-' * 80`, the padding of `center` and `batch`,
/// the indentation of `indent` and `tojson`, or the lists that `slice` makes.
///
/// Jinja2 has no such limit:
/// Python raises `MemoryError` when an allocation fails,
/// but Swift stops the process.
/// So swift-jinja throws before it allocates more than this.
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
