import Foundation
import Testing

import Jinja

/// Renders each case in `Conformance/cases/` and compares the result
/// with the output that Jinja2 recorded in `Conformance/jinja2.jsonl`.
///
/// A case listed in `Conformance/known-differences.json` must give
/// the swift-jinja result recorded there instead,
/// so that the test fails both when a case regresses
/// and when a known difference changes or is fixed.
/// When both engines fail, the case agrees; error messages are not compared.
///
/// `uv run Tools/conformance/regenerate.py` rewrites both files.
/// See `Tools/conformance/README.md`.
@Suite("Jinja2 conformance")
struct ConformanceTests {
    /// The suite's data, or the error that stopped it from loading.
    static let corpus = Result { try Corpus.load() }

    /// Every case except known crashes and hangs, which would stop the test run.
    static let renderableCases: [Case] = {
        guard case .success(let corpus) = corpus else { return [] }
        return corpus.cases.filter { corpus.known[$0.id]?.isCrashOrHang != true }
    }()

    @Test("The corpus, Jinja2 results, and known differences agree")
    func corpusIsConsistent() throws {
        let corpus = try Self.corpus.get()
        let ids = Set(corpus.cases.map(\.id))
        #expect(!ids.isEmpty)
        #expect(ids.count == corpus.cases.count, "Case IDs must be unique")
        #expect(Set(corpus.jinja2.keys) == ids, "Run regenerate.py: jinja2.jsonl does not match the corpus")
        let unknown = Set(corpus.known.keys).subtracting(ids)
        #expect(unknown.isEmpty, "Run regenerate.py: known differences without a case: \(unknown.sorted())")
        for difference in corpus.known.values {
            #expect(corpus.causes[difference.cause] != nil, "\(difference.id) has an undescribed cause")
        }
    }

    @Test("Renders like Jinja2", arguments: renderableCases)
    func rendersLikeJinja2(_ testCase: Case) throws {
        let corpus = try Self.corpus.get()
        let jinja2 = try #require(corpus.jinja2[testCase.id]).expandingDates()
        let actual = onLargeStack { testCase.render() }

        guard let known = corpus.known[testCase.id] else {
            if !actual.agrees(with: jinja2) {
                Issue.record(
                    """
                    \(testCase.id) differs from Jinja2 \(corpus.jinja2Version).
                    \(describe(expected: jinja2, actual: actual))
                    Fix the regression, or run `uv run Tools/conformance/regenerate.py` \
                    to record an intended difference.
                    """
                )
            }
            return
        }

        if actual.agrees(with: jinja2) {
            Issue.record(
                """
                \(testCase.id) now matches Jinja2 \(corpus.jinja2Version) \
                (known difference: \(known.cause)).
                Run `uv run Tools/conformance/regenerate.py` to remove it from known-differences.json.
                """
            )
        } else if !actual.agrees(with: known.swift.expandingDates()) {
            Issue.record(
                """
                \(testCase.id) changed (known difference: \(known.cause)).
                \(describe(expected: known.swift.expandingDates(), actual: actual))
                Run `uv run Tools/conformance/regenerate.py` to record the new result.
                """
            )
        }
    }
}

// MARK: - Corpus

extension ConformanceTests {
    /// One template, context, and environment to render.
    struct Case: Sendable, CustomTestStringConvertible {
        let id: String
        let template: String
        let context: [String: Value]
        let mode: String
        let options: Template.Options

        var testDescription: String { id }

        /// Renders the case the way Tools/conformance/jinja-render does.
        func render() -> RenderResult {
            do {
                let template = try Template(template, with: options)
                let environment = Environment()
                // A default Jinja2 environment writes HTML-safe, sorted, ASCII JSON;
                // transformers uses json.dumps with ensure_ascii=False.
                environment.policies = mode == "transformers" ? .transformers : .jinja2
                return RenderResult(ok: true, output: try template.render(context, environment: environment))
            } catch {
                return RenderResult(ok: false, error: "\(type(of: error)): \(error)")
            }
        }
    }

    /// The result of rendering a case: output, or an error.
    struct RenderResult: Decodable, Sendable {
        var ok: Bool
        var output: String?
        var error: String?

        /// True if both have the same output, or both failed.
        func agrees(with other: RenderResult) -> Bool {
            ok == other.ok && (!ok || output == other.output)
        }

        /// Replaces each "[strftime_now <format>]" marker
        /// with the current date from swift-jinja's strftime_now,
        /// because recorded output can't contain the date of a later test run.
        func expandingDates() -> RenderResult {
            guard let output, output.contains("[strftime_now ") else { return self }
            var expanded = ""
            var rest = Substring(output)
            while let start = rest.range(of: "[strftime_now "),
                let end = rest[start.upperBound...].firstIndex(of: "]")
            {
                expanded += rest[..<start.lowerBound]
                let format = String(rest[start.upperBound ..< end])
                let date = try? Globals.strftimeNow([.string(format)], [:], Environment())
                if case .string(let text)? = date {
                    expanded += text
                } else {
                    expanded += rest[start.lowerBound ... end]
                }
                rest = rest[rest.index(after: end)...]
            }
            expanded += rest
            var result = self
            result.output = expanded
            return result
        }
    }

    struct KnownDifference: Decodable, Sendable {
        let id: String
        let cause: String
        let `class`: String
        let swift: RenderResult

        /// The swift-jinja process crashed or hung on this case when it was recorded.
        var isCrashOrHang: Bool { `class` == "crash" || `class` == "timeout" }
    }

    struct KnownDifferences: Decodable {
        let jinja2: String
        let causes: [String: String]
        let differences: [KnownDifference]
    }

    struct Corpus: Sendable {
        let cases: [Case]
        let jinja2: [String: RenderResult]
        let jinja2Version: String
        let known: [String: KnownDifference]
        let causes: [String: String]

        struct LoadError: Error, CustomStringConvertible {
            let description: String
        }

        static func load() throws -> Corpus {
            guard let root = Bundle.module.url(forResource: "Conformance", withExtension: nil) else {
                throw LoadError(description: "The Conformance resource directory is missing")
            }

            var cases: [Case] = []
            let caseFiles = try FileManager.default.contentsOfDirectory(
                at: root.appendingPathComponent("cases"),
                includingPropertiesForKeys: nil
            )
            for file in caseFiles.filter({ $0.pathExtension == "jsonl" }).sorted(by: { $0.path < $1.path }) {
                for line in try lines(of: file) {
                    cases.append(try parseCase(line, root: root))
                }
            }

            let decoder = JSONDecoder()
            struct Recorded: Decodable {
                let id: String
                let ok: Bool
                let output: String?
                let error: String?
            }
            var jinja2: [String: RenderResult] = [:]
            for line in try lines(of: root.appendingPathComponent("jinja2.jsonl")) {
                let recorded = try decoder.decode(Recorded.self, from: Data(line.utf8))
                jinja2[recorded.id] = RenderResult(ok: recorded.ok, output: recorded.output, error: recorded.error)
            }

            let knownData = try Data(contentsOf: root.appendingPathComponent("known-differences.json"))
            let known = try decoder.decode(KnownDifferences.self, from: knownData)
            return Corpus(
                cases: cases,
                jinja2: jinja2,
                jinja2Version: known.jinja2,
                known: Dictionary(known.differences.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
                causes: known.causes
            )
        }

        private static func lines(of file: URL) throws -> [Substring] {
            try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: true)
        }

        private static func parseCase(_ line: Substring, root: URL) throws -> Case {
            guard case .object(let fields) = try parseOrderedJSON(String(line)),
                case .string(let id)? = fields["id"]
            else {
                throw LoadError(description: "A case is not an object with an id: \(line.prefix(80))")
            }

            let template: String
            if case .string(let source)? = fields["template"] {
                template = source
            } else if case .string(let path)? = fields["template_file"] {
                template = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            } else {
                throw LoadError(description: "\(id) has no template")
            }

            var context: [String: Value] = [:]
            if case .object(let values)? = fields["context"] {
                for (key, value) in values {
                    context[key.stringValue] = value
                }
            }

            var mode = "default"
            if case .string(let value)? = fields["mode"] {
                mode = value
            }

            func option(_ key: String) -> Bool {
                guard case .object(let options)? = fields["options"], case .boolean(let value)? = options[.string(key)]
                else { return false }
                return value
            }
            // transformers compiles chat templates with trim_blocks and lstrip_blocks.
            let options =
                mode == "transformers"
                ? Template.Options(lstripBlocks: true, trimBlocks: true)
                : Template.Options(
                    lstripBlocks: option("lstrip_blocks"),
                    trimBlocks: option("trim_blocks"),
                    keepTrailingNewline: option("keep_trailing_newline")
                )

            return Case(id: id, template: template, context: context, mode: mode, options: options)
        }
    }
}

// MARK: - Helpers

/// Runs `body` on a thread with a 64 MB stack and waits for it.
///
/// Some cases nest deeply, such as an `if` with hundreds of `elif` branches.
/// They render on a main thread's 8 MB stack, as in jinja-render,
/// but overflow the smaller stack of a Swift Testing worker thread.
private func onLargeStack(
    _ body: @escaping @Sendable () -> ConformanceTests.RenderResult
) -> ConformanceTests.RenderResult {
    final class Box: @unchecked Sendable {
        var value: ConformanceTests.RenderResult?
    }
    let box = Box()
    let done = DispatchSemaphore(value: 0)
    let thread = Thread {
        box.value = body()
        done.signal()
    }
    thread.stackSize = 64 << 20
    thread.start()
    done.wait()
    return box.value!
}

// MARK: - Messages

/// Describes two results, showing where their outputs first differ.
private func describe(expected: ConformanceTests.RenderResult, actual: ConformanceTests.RenderResult) -> String {
    func text(_ result: ConformanceTests.RenderResult) -> String {
        result.ok ? String(reflecting: result.output ?? "") : "error: \(result.error ?? "")"
    }
    guard expected.ok, actual.ok, let a = expected.output, let b = actual.output, a.count + b.count > 400 else {
        return "Expected: \(text(expected))\nActual:   \(text(actual))"
    }
    let common = zip(a, b).prefix { $0 == $1 }.count
    let start = max(0, common - 60)
    func excerpt(_ s: String) -> String {
        String(reflecting: String(s.dropFirst(start).prefix(160)))
    }
    return """
        Outputs first differ at character \(common).
        Expected: …\(excerpt(a))…
        Actual:   …\(excerpt(b))…
        """
}
