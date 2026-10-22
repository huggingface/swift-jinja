// Renders conformance cases with swift-jinja, one per line.
//
// Reads one JSON case per line on standard input
// and writes one JSON result per line on standard output,
// flushing after each one.
// A driver can keep one process running,
// detect a crash from the end of output,
// and detect a hang with a timeout.
//
// Case fields: "template", "context", "mode" ("default" or "transformers"),
// "options" ("trim_blocks", "lstrip_blocks", "keep_trailing_newline"),
// and optionally "strftime_now", a list of formats.
// Result fields: "ok", and "output" or "error";
// and "strftime_now", the current date in each requested format.
//
// Tests/JinjaTests/ConformanceTests.swift renders cases the same way.

import Foundation
import Jinja

func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: []) else {
        FileHandle.standardOutput.write(#"{"ok": false, "error": "HARNESS: unencodable result"}"#.data(using: .utf8)!)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
        return
    }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

func boolOption(_ options: Value?, _ key: String) -> Bool {
    guard case .object(let options)? = options, case .boolean(let value)? = options[.string(key)] else {
        return false
    }
    return value
}

while let line = readLine(strippingNewline: true) {
    if line.isEmpty { continue }
    guard case .object(let fields) = (try? parseOrderedJSON(line)) ?? .null,
        case .string(let source)? = fields["template"]
    else {
        emit(["ok": false, "error": "HARNESS: bad case"])
        continue
    }
    var mode = "default"
    if case .string(let value)? = fields["mode"] {
        mode = value
    }

    // transformers compiles chat templates with trim_blocks and lstrip_blocks.
    let options: Template.Options
    if mode == "transformers" {
        options = Template.Options(lstripBlocks: true, trimBlocks: true)
    } else {
        options = Template.Options(
            lstripBlocks: boolOption(fields["options"], "lstrip_blocks"),
            trimBlocks: boolOption(fields["options"], "trim_blocks"),
            keepTrailingNewline: boolOption(fields["options"], "keep_trailing_newline")
        )
    }

    var context: [String: Value] = [:]
    if case .object(let values)? = fields["context"] {
        for (key, value) in values {
            context[key.stringValue] = value
        }
    }

    do {
        let template = try Template(source, with: options)
        let environment = Environment()
        // A default Jinja2 environment writes HTML-safe, sorted, ASCII JSON;
        // transformers uses json.dumps with ensure_ascii=False.
        environment.policies = mode == "transformers" ? .transformers : .jinja2
        let output = try template.render(context, environment: environment)
        var result: [String: Any] = ["ok": true, "output": output]
        // Report what strftime_now returns now for each requested format,
        // so that a driver can compare output that contains the current date.
        if case .array(let formats)? = fields["strftime_now"] {
            var dates: [String: String] = [:]
            for case .string(let format) in formats {
                if case .string(let date) = try Globals.strftimeNow([.string(format)], [:], environment) {
                    dates[format] = date
                }
            }
            result["strftime_now"] = dates
        }
        emit(result)
    } catch {
        emit(["ok": false, "error": "\(type(of: error)): \(error)"])
    }
}
