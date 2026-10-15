#if canImport(CryptoKit)
import CoreFoundation
import CryptoKit
import Foundation
import Testing

@testable import Jinja

/// Optional external-fixture qualification in addition to the self-contained
/// parser tests. Source bytes are never normalized or replaced by this test.
@Suite("Official GLM 5.3 template compatibility")
struct ExternalGLM53TemplateTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GLM53_PROMPT_FIXTURE_DIR"] != nil))
    func completeOfficialTemplateMatchesAllRenderGoldens() throws {
        let path = try #require(ProcessInfo.processInfo.environment["GLM53_PROMPT_FIXTURE_DIR"])
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let data = try Data(contentsOf: directory.appendingPathComponent("chat_template.jinja"))
        #expect(data.count == 10_950)
        #expect(hash(data) == "0c4099f3382d6c92700dfb99725025360966fd73032f0ecf32377c0d9e6309c5")
        let corpus = try #require(JSONSerialization.jsonObject(with:
            Data(contentsOf: directory.appendingPathComponent("goldens.json"))) as? [String: Any])
        let cases = try #require(corpus["cases"] as? [[String: Any]])
        #expect(cases.count == 7)
        let source = try #require(String(data: data, encoding: .utf8))
        // Compile the whole original source, including numeric attributes,
        // nested macros, namespace writes, and break statements.
        let template = try Template(source, with: .init(lstripBlocks: true, trimBlocks: true))
        for fixture in cases {
            let id = try #require(fixture["id"] as? String)
            let request = try #require(fixture["request"] as? [String: Any])
            var messages = try #require(request["messages"] as? [[String: Any]])
            for index in messages.indices {
                guard var calls = messages[index]["tool_calls"] as? [[String: Any]] else { continue }
                for callIndex in calls.indices {
                    var function = try #require(calls[callIndex]["function"] as? [String: Any])
                    let arguments = try #require(function["arguments"] as? String)
                    function["arguments"] = try JSONSerialization.jsonObject(with: Data(arguments.utf8))
                    calls[callIndex]["function"] = function
                }
                messages[index]["tool_calls"] = calls
            }
            let expectedContext = try #require(fixture["expected_context"] as? [String: Any])
            var context: Context = [
                "messages": try value(messages), "add_generation_prompt": .boolean(true),
            ]
            if let tools = request["tools"] { context["tools"] = try value(tools) }
            for (name, raw) in expectedContext { context[name] = try value(raw) }
            let rendered = try template.render(context)
            let expected = try #require(fixture["rendered"] as? String)
            let expectedHash = try #require(fixture["rendered_sha256"] as? String)
            #expect(Data(rendered.utf8) == Data(expected.utf8), "\(id)")
            #expect(hash(Data(rendered.utf8)) == expectedHash, "\(id)")
        }
    }

    private func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func value(_ raw: Any) throws -> Value {
        if raw is NSNull { return .null }
        if let string = raw as? String { return .string(string) }
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .boolean(number.boolValue) }
            if let integer = number as? Int { return .int(integer) }
            return .double(number.doubleValue)
        }
        if let array = raw as? [Any] { return .array(try array.map(value)) }
        if let object = raw as? [String: Any] {
            var ordered = OrderedDictionary<String, Value>()
            for (key, child) in object.sorted(by: { $0.key < $1.key }) {
                ordered[key] = try value(child)
            }
            return .object(ordered)
        }
        throw JinjaError.runtime("unsupported external fixture value")
    }
}
#endif
