//
//  PerformanceTests.swift
//
//
//  Created by Terence Pae on 2025/09/05.
//

import XCTest

@testable import Jinja

final class PerformanceTests: XCTestCase {
    // Simple micro-benchmark helper
    private func measureMs(iterations: Int = 100, warmup: Int = 10, _ body: () throws -> Void) rethrows -> Double {
        // Warmup
        for _ in 0 ..< warmup { try body() }

        var total: Double = 0
        for _ in 0 ..< iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            try body()
            let end = DispatchTime.now().uptimeNanoseconds
            total += Double(end - start) / 1_000_000.0
        }
        return total / Double(iterations)
    }

    func testTemplateRenderPerformance() throws {
        let template = try Template(ChatTemplate.llama3_2)

        let avgMs = try measureMs {
            _ = try template.render([
                "messages": Messages.weatherQuery,
                "add_generation_prompt": true,
            ])
        }
        print("Template.render avg: \(String(format: "%.3f", avgMs)) ms")
    }

    func testPipelineStagesPerformance() throws {
        let tpl = ChatTemplate.llama3_2

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
        try env.set(name: "messages", value: Messages.weatherQuery)
        try env.set(name: "add_generation_prompt", value: false)

        let interpreter = Interpreter(env: env)
        let runMs = try measureMs {
            _ = try interpreter.run(program: program)
        }

        print(
            "tokenize avg: \(String(format: "%.3f", tokenizeMs)) ms | parse avg: \(String(format: "%.3f", parseMs)) ms | run avg: \(String(format: "%.3f", runMs)) ms"
        )
    }
}
