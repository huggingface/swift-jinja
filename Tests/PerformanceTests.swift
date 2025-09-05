//
//  PerformanceTests.swift
//

import XCTest

@testable import Jinja

final class PerformanceTests: XCTestCase {
    // Simple micro-benchmark helper
    private func measureMs(iterations: Int = 100, warmup: Int = 10, _ body: () throws -> Void) rethrows -> Double {
        // Warmup
        for _ in 0..<warmup { try body() }

        var total: Double = 0
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            try body()
            let end = DispatchTime.now().uptimeNanoseconds
            total += Double(end - start) / 1_000_000.0
        }
        return total / Double(iterations)
    }

    func testTemplateRenderPerformance() throws {
        let templateString = """
        {% for i in range(0, 100) %}
        {{ i }} {{ 'x' ~ 'x' }}\n
        {% endfor %}
        """
        let template = try Template(templateString)

        let avgMs = try measureMs {
            _ = try template.render([:])
        }
        print("Template.render avg: \(String(format: "%.3f", avgMs)) ms")
    }

    func testPipelineStagesPerformance() throws {
        let tpl = """
        {% set ns = namespace(total=0) %}
        {% for i in range(0, 100) %}
        {% set ns.total = ns.total + i %}
        {% endfor %}
        {{ ns.total }}
        """

        // tokenize
        let tokenizeMs = try measureMs {
            _ = try tokenize(tpl)
        }

        let tokens = try tokenize(tpl)

        // parse
        let parseMs = try measureMs {
            _ = try parse(tokens: tokens)
        }

        let program = try parse(tokens: tokens)

        // interpret
        let env = Environment()
        try env.set(name: "true", value: true)
        try env.set(name: "false", value: false)
        try env.set(name: "none", value: NullValue())
        try env.set(name: "range", value: range)

        let interpreter = Interpreter(env: env)
        let runMs = try measureMs {
            _ = try interpreter.run(program: program)
        }

        print("tokenize avg: \(String(format: "%.3f", tokenizeMs)) ms | parse avg: \(String(format: "%.3f", parseMs)) ms | run avg: \(String(format: "%.3f", runMs)) ms")
    }
}


