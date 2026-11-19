import Foundation
import OrderedCollections
import Testing

@testable import Jinja

@Suite("Macro Tests")
struct MacroTests {
    @Test("Basic initialization")
    func basicInit() {
        let macro = Macro(
            name: "greeting",
            parameters: ["name", "title"],
            defaults: ["title": .string("Mr.")],
            body: [.text("Hello")]
        )

        #expect(macro.name == "greeting")
        #expect(macro.parameters == ["name", "title"])
        #expect(macro.defaults == ["title": .string("Mr.")])
        #expect(macro.body == [.text("Hello")])
    }

    /// Jinja2 prints a macro with its `repr()`.
    /// Expected strings were rendered with jinja2 3.1.6.
    @Test("Printing a macro writes its Python representation")
    func printMacro() throws {
        let template = try Template("{% macro m1(p='') %}{% endmacro %}{{ m1 }} {{ [m1] }}")
        #expect(try template.render([:]) == "<Macro 'm1'> [<Macro 'm1'>]")
    }

    @Test("Initialization with empty defaults and body")
    func emptyDefaultsAndBody() {
        let macro = Macro(
            name: "empty",
            parameters: [],
            defaults: [:],
            body: []
        )

        #expect(macro.name == "empty")
        #expect(macro.parameters.isEmpty)
        #expect(macro.defaults.isEmpty)
        #expect(macro.body.isEmpty)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let macro = Macro(
            name: "render",
            parameters: ["content", "class"],
            defaults: ["class": .string("default")],
            body: [.text("<div>"), .expression(.identifier("content")), .text("</div>")]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(macro)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Macro.self, from: data)

        #expect(decoded.name == macro.name)
        #expect(decoded.parameters == macro.parameters)
        #expect(decoded.body == macro.body)
        #expect(decoded.defaults.count == macro.defaults.count)
        #expect(decoded.defaults["class"] == macro.defaults["class"])
    }

    @Test("Decoded defaults are key-sorted")
    func decodedDefaultsAreKeySorted() throws {
        let macro = Macro(
            name: "render",
            parameters: ["a", "z"],
            defaults: ["z": .integer(1), "a": .integer(2)],
            body: [.text("x")]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(macro)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Macro.self, from: data)

        #expect(Array(decoded.defaults.keys) == ["a", "z"])
    }

    @Test("Codable round-trip with empty defaults")
    func codableRoundTripEmptyDefaults() throws {
        let macro = Macro(
            name: "simple",
            parameters: ["x"],
            defaults: [:],
            body: [.text("hi")]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(macro)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Macro.self, from: data)

        #expect(decoded.name == macro.name)
        #expect(decoded.parameters == macro.parameters)
        #expect(decoded.defaults.isEmpty)
        #expect(decoded.body == macro.body)
    }

    @Test("Equatable - equal macros")
    func equalMacros() {
        let macro1 = Macro(
            name: "test",
            parameters: ["a"],
            defaults: ["a": .integer(1)],
            body: [.text("body")]
        )
        let macro2 = Macro(
            name: "test",
            parameters: ["a"],
            defaults: ["a": .integer(1)],
            body: [.text("body")]
        )

        #expect(macro1 == macro2)
    }

    @Test("Equatable - different macros")
    func differentMacros() {
        let macro1 = Macro(
            name: "test",
            parameters: ["a"],
            defaults: [:],
            body: [.text("body")]
        )
        let macro2 = Macro(
            name: "other",
            parameters: ["a"],
            defaults: [:],
            body: [.text("body")]
        )

        #expect(macro1 != macro2)
    }

    @Test("Hashable - equal macros have same hash")
    func hashableEqual() {
        let macro1 = Macro(
            name: "hash",
            parameters: ["x"],
            defaults: ["x": .boolean(true)],
            body: [.text("content")]
        )
        let macro2 = Macro(
            name: "hash",
            parameters: ["x"],
            defaults: ["x": .boolean(true)],
            body: [.text("content")]
        )

        #expect(macro1.hashValue == macro2.hashValue)

        let set: Set<Macro> = [macro1, macro2]
        #expect(set.count == 1)
    }

    @Test("Hashable - different macros in a set")
    func hashableDifferent() {
        let macro1 = Macro(
            name: "a",
            parameters: [],
            defaults: [:],
            body: []
        )
        let macro2 = Macro(
            name: "b",
            parameters: [],
            defaults: [:],
            body: []
        )

        let set: Set<Macro> = [macro1, macro2]
        #expect(set.count == 2)
    }
}
