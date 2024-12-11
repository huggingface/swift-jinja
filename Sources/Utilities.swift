//
//  Utilities.swift
//
//
//  Created by John Mai on 2024/3/20.
//

import Foundation

func range(start: Int, stop: Int? = nil, step: Int = 1) -> [Int] {
    let stopUnwrapped = stop ?? start
    let startValue = stop == nil ? 0 : start
    let stopValue = stop == nil ? start : stopUnwrapped

    return stride(from: startValue, to: stopValue, by: step).map { $0 }
}

func slice<T>(_ array: [T], start: Int? = nil, stop: Int? = nil, step: Int? = 1) -> [T] {
    let arrayCount = array.count
    let startValue = start ?? 0
    let stopValue = stop ?? arrayCount
    let step = step ?? 1
    var slicedArray = [T]()

    if step > 0 {
        let startIndex = startValue < 0 ? max(arrayCount + startValue, 0) : min(startValue, arrayCount)
        let stopIndex = stopValue < 0 ? max(arrayCount + stopValue, 0) : min(stopValue, arrayCount)
        for i in stride(from: startIndex, to: stopIndex, by: step) {
            slicedArray.append(array[i])
        }
    } else {
        let startIndex = startValue < 0 ? max(arrayCount + startValue, -1) : min(startValue, arrayCount - 1)
        let stopIndex = stopValue < -1 ? max(arrayCount + stopValue, -1) : min(stopValue, arrayCount - 1)
        for i in stride(from: startIndex, through: stopIndex, by: step) {
            slicedArray.append(array[i])
        }
    }

    return slicedArray
}

func toJSON(_ input: any RuntimeValue, indent: Int? = nil, depth: Int = 0) throws -> String {
    let currentDepth = depth

    switch input {
        case is NullValue, is UndefinedValue:
            return "null"

        case let value as NumericValue:
            return String(describing: value.value)

        case let value as StringValue:
            return "\"\(value.value)\""  // Directly wrap string in quotes

        case let value as BooleanValue:
            return value.value ? "true" : "false"

        case let arr as ArrayValue:
            let indentValue = indent != nil ? String(repeating: " ", count: indent!) : ""
            let basePadding = "\n" + String(repeating: indentValue, count: currentDepth)
            let childrenPadding = basePadding + indentValue // Depth + 1

            let core = try arr.value.map { try toJSON($0, indent: indent, depth: currentDepth + 1) }

            if indent != nil {
                return "[\(childrenPadding)\(core.joined(separator: ",\(childrenPadding)"))\(basePadding)]"
            } else {
                return "[\(core.joined(separator: ", "))]"
            }

        case let obj as ObjectValue:
            let indentValue = indent != nil ? String(repeating: " ", count: indent!) : ""
            let basePadding = "\n" + String(repeating: indentValue, count: currentDepth)
            let childrenPadding = basePadding + indentValue // Depth + 1

            let core = try obj.value.map { key, value in
                let v = "\"\(key)\": \(try toJSON(value, indent: indent, depth: currentDepth + 1))"
                return indent != nil ? "\(childrenPadding)\(v)" : v
            }

            if indent != nil {
                return "{\(core.joined(separator: ","))\(basePadding)}"
            } else {
                return "{\(core.joined(separator: ", "))}"
            }

        default:
            throw JinjaError.runtime("Cannot convert to JSON: \(type(of: input))")
    }
}

// Helper function to convert values to JSON strings
private func jsonString(_ value: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value)
    guard let string = String(data: data, encoding: .utf8) else {
        throw JinjaError.runtime("Failed to convert value to JSON string")
    }
    return string
}

extension String {
    func titleCase() -> String {
        self.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    func indent(_ width: Int, first: Bool = false, blank: Bool = false) -> String {
        let indent = String(repeating: " ", count: width)
        return self.components(separatedBy: .newlines)
            .enumerated()
            .map { index, line in
                if line.isEmpty && !blank {
                    return line
                }
                if index == 0 && !first {
                    return line
                }
                return indent + line
            }
            .joined(separator: "\n")
    }
}

