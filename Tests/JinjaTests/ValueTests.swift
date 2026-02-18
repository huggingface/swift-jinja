import Foundation
import Testing

@testable import Jinja

@Suite("Value Tests")
struct ValueTests {
    @Test("Initialization from Any")
    func initFromAny() throws {
        #expect(try Value(any: nil) == Value.null)
        #expect(try Value(any: "hello") == Value.string("hello"))
        #expect(try Value(any: 42) == Value.int(42))
        #expect(try Value(any: 3.14) == Value.double(3.14))
        #expect(try Value(any: Float(2.5)) == Value.double(2.5))
        #expect(try Value(any: true) == Value.boolean(true))

        let arrayValue = try Value(any: [1, "test", nil])
        if case let .array(values) = arrayValue {
            #expect(values.count == 3)
            #expect(values[0] == Value.int(1))
            #expect(values[1] == Value.string("test"))
            #expect(values[2] == Value.null)
        } else {
            Issue.record("Expected array value")
        }

        let dictValue = try Value(any: ["key": "value", "num": 42])
        if case let .object(dict) = dictValue {
            #expect(dict["key"] == Value.string("value"))
            #expect(dict["num"] == Value.int(42))
        } else {
            Issue.record("Expected object value")
        }

        #expect(throws: JinjaError.self) {
            _ = try Value(any: NSObject())
        }

        let orderedDictValue = try Value(any: Value.object(["key": "value", "num": 42]))
        if case let .object(dict) = orderedDictValue {
            #expect(dict["key"] == Value.string("value"))
            #expect(dict["num"] == Value.int(42))
            #expect(Array(dict.keys) == ["key", "num"])
        } else {
            Issue.record("Expected object value")
        }
    }

    @Test("Literal conformances")
    func literals() {
        let stringValue: Value = "test"
        #expect(stringValue == Value.string("test"))

        let intValue: Value = 42
        #expect(intValue == Value.int(42))

        let doubleValue: Value = 3.14
        #expect(doubleValue == Value.double(3.14))

        let boolValue: Value = true
        #expect(boolValue == Value.boolean(true))

        let arrayValue: Value = [1, 2, 3]
        if case let .array(values) = arrayValue {
            #expect(values.count == 3)
            #expect(values[0] == Value.int(1))
            #expect(values[1] == Value.int(2))
            #expect(values[2] == Value.int(3))
        } else {
            Issue.record("Expected array value")
        }

        let dictValue: Value = ["a": 1, "b": 2]
        if case let .object(dict) = dictValue {
            #expect(dict["a"] == Value.int(1))
            #expect(dict["b"] == Value.int(2))
        } else {
            Issue.record("Expected object value")
        }

        let nilValue: Value = nil
        #expect(nilValue == Value.null)
    }

    @Test("CustomStringConvertible conformance")
    func description() {
        #expect(Value.string("test").description == "test")
        #expect(Value.int(42).description == "42")
        #expect(Value.double(3.14).description == "3.14")
        #expect(Value.boolean(true).description == "true")
        #expect(Value.boolean(false).description == "false")
        #expect(Value.null.description == "")
        #expect(Value.undefined.description == "")
        #expect(Value.array([Value.int(1), Value.int(2)]).description == "[1, 2]")
        #expect(Value.object(["a": Value.int(1)]).description == "{a: 1}")
    }

    @Test("isTruthy behavior")
    func isTruthy() {
        #expect(Value.null.isTruthy == false)
        #expect(Value.undefined.isTruthy == false)
        #expect(Value.boolean(true).isTruthy == true)
        #expect(Value.boolean(false).isTruthy == false)
        #expect(Value.string("").isTruthy == false)
        #expect(Value.string("hello").isTruthy == true)
        #expect(Value.double(0.0).isTruthy == false)
        #expect(Value.double(1.0).isTruthy == true)
        #expect(Value.int(0).isTruthy == false)
        #expect(Value.int(1).isTruthy == true)
        #expect(Value.array([]).isTruthy == false)
        #expect(Value.array([Value.int(1)]).isTruthy == true)
        #expect(Value.object([:]).isTruthy == false)
        #expect(Value.object(["key": Value.string("value")]).isTruthy == true)
    }

    @Test("Encodable conformance")
    func encodable() throws {
        let encoder = JSONEncoder()

        // Test primitive values
        let stringData = try encoder.encode(Value.string("hello"))
        let stringJSON = String(data: stringData, encoding: .utf8)!
        #expect(stringJSON == "\"hello\"")

        let intData = try encoder.encode(Value.int(42))
        let intJSON = String(data: intData, encoding: .utf8)!
        #expect(intJSON == "42")

        let numberData = try encoder.encode(Value.double(3.14))
        let numberJSON = String(data: numberData, encoding: .utf8)!
        #expect(numberJSON == "3.14")

        let boolData = try encoder.encode(Value.boolean(true))
        let boolJSON = String(data: boolData, encoding: .utf8)!
        #expect(boolJSON == "true")

        let nullData = try encoder.encode(Value.null)
        let nullJSON = String(data: nullData, encoding: .utf8)!
        #expect(nullJSON == "null")

        let undefinedData = try encoder.encode(Value.undefined)
        let undefinedJSON = String(data: undefinedData, encoding: .utf8)!
        #expect(undefinedJSON == "null")

        // Test array encoding
        let arrayValue = Value.array([Value.int(1), Value.string("test"), Value.boolean(false)])
        let arrayData = try encoder.encode(arrayValue)
        let arrayJSON = String(data: arrayData, encoding: .utf8)!
        #expect(arrayJSON == "[1,\"test\",false]")

        // Test object encoding
        var objectDict = OrderedDictionary<String, Value>()
        objectDict["name"] = Value.string("John")
        objectDict["age"] = Value.int(30)
        objectDict["active"] = Value.boolean(true)
        let objectValue = Value.object(objectDict)
        let objectData = try encoder.encode(objectValue)
        let objectJSON = String(data: objectData, encoding: .utf8)!
        #expect(objectJSON.contains("\"name\":\"John\""))
        #expect(objectJSON.contains("\"age\":30"))
        #expect(objectJSON.contains("\"active\":true"))

        // Test nested structures
        let nestedArray = Value.array([
            Value.string("item1"),
            Value.object(["nested": Value.int(42)]),
            Value.array([Value.boolean(true), Value.null]),
        ])
        let nestedArrayData = try encoder.encode(nestedArray)
        let nestedArrayJSON = String(data: nestedArrayData, encoding: .utf8)!
        #expect(nestedArrayJSON.contains("\"item1\""))
        #expect(nestedArrayJSON.contains("\"nested\":42"))
        #expect(nestedArrayJSON.contains("true"))
        #expect(nestedArrayJSON.contains("null"))

        // Test function encoding should throw
        let functionValue = Value.function { _, _, _ in Value.null }
        #expect(throws: EncodingError.self) {
            _ = try encoder.encode(functionValue)
        }
    }

    @Test("Decodable conformance")
    func decodable() throws {
        let decoder = JSONDecoder()

        // Test primitive values
        let stringData = "\"hello\"".data(using: .utf8)!
        let stringValue = try decoder.decode(Value.self, from: stringData)
        #expect(stringValue == Value.string("hello"))

        let intData = "42".data(using: .utf8)!
        let intValue = try decoder.decode(Value.self, from: intData)
        #expect(intValue == Value.int(42))

        let numberData = "3.14".data(using: .utf8)!
        let numberValue = try decoder.decode(Value.self, from: numberData)
        #expect(numberValue == Value.double(3.14))

        let boolData = "true".data(using: .utf8)!
        let boolValue = try decoder.decode(Value.self, from: boolData)
        #expect(boolValue == Value.boolean(true))

        let nullData = "null".data(using: .utf8)!
        let nullValue = try decoder.decode(Value.self, from: nullData)
        #expect(nullValue == Value.null)

        // Test array decoding
        let arrayData = "[1,\"test\",false]".data(using: .utf8)!
        let arrayValue = try decoder.decode(Value.self, from: arrayData)
        if case let .array(values) = arrayValue {
            #expect(values.count == 3)
            #expect(values[0] == Value.int(1))
            #expect(values[1] == Value.string("test"))
            #expect(values[2] == Value.boolean(false))
        } else {
            Issue.record("Expected array value")
        }

        // Test object decoding
        let objectData = "{\"name\":\"John\",\"age\":30,\"active\":true}".data(using: .utf8)!
        let objectValue = try decoder.decode(Value.self, from: objectData)
        if case let .object(dict) = objectValue {
            #expect(dict["name"] == Value.string("John"))
            #expect(dict["age"] == Value.int(30))
            #expect(dict["active"] == Value.boolean(true))
        } else {
            Issue.record("Expected object value")
        }

        // Test nested structures
        let nestedData = "[\"item1\",{\"nested\":42},[true,null]]".data(using: .utf8)!
        let nestedValue = try decoder.decode(Value.self, from: nestedData)
        if case let .array(values) = nestedValue {
            #expect(values.count == 3)
            #expect(values[0] == Value.string("item1"))

            if case let .object(nestedDict) = values[1] {
                #expect(nestedDict["nested"] == Value.int(42))
            } else {
                Issue.record("Expected nested object")
            }

            if case let .array(nestedArray) = values[2] {
                #expect(nestedArray.count == 2)
                #expect(nestedArray[0] == Value.boolean(true))
                #expect(nestedArray[1] == Value.null)
            } else {
                Issue.record("Expected nested array")
            }
        } else {
            Issue.record("Expected array value")
        }
    }

    @Test("Round-trip encoding/decoding")
    func roundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let testValues: [Value] = [
            .string("hello"),
            .int(42),
            .double(3.14),
            .boolean(true),
            .boolean(false),
            .null,
            .array([Value.int(1), Value.string("test"), Value.boolean(false)]),
            .object(["key1": Value.string("value1"), "key2": Value.int(123)]),
        ]

        for originalValue in testValues {
            let data = try encoder.encode(originalValue)
            let decodedValue = try decoder.decode(Value.self, from: data)
            #expect(decodedValue == originalValue, "Round-trip failed for \(originalValue)")
        }
    }

    @Test("Complex nested structures")
    func complexNestedStructures() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Create a complex nested structure
        var complexDict = OrderedDictionary<String, Value>()
        complexDict["users"] = Value.array([
            Value.object([
                "id": Value.int(1),
                "name": Value.string("Alice"),
                "active": Value.boolean(true),
                "scores": Value.array([Value.double(95.5), Value.double(87.2), Value.double(92.0)]),
            ]),
            Value.object([
                "id": Value.int(2),
                "name": Value.string("Bob"),
                "active": Value.boolean(false),
                "scores": Value.array([Value.double(78.1), Value.double(81.5)]),
            ]),
        ])
        complexDict["metadata"] = Value.object([
            "total": Value.int(2),
            "lastUpdated": Value.string("2024-01-01T00:00:00Z"),
            "version": Value.double(1.1),
        ])
        complexDict["settings"] = Value.null

        let complexValue = Value.object(complexDict)

        // Encode and decode
        let data = try encoder.encode(complexValue)
        let decodedValue = try decoder.decode(Value.self, from: data)

        // Verify specific nested values
        if case let .object(decodedDict) = decodedValue {
            if case let .array(users) = decodedDict["users"] {
                #expect(users.count == 2)

                if case let .object(user1) = users[0] {
                    #expect(user1["name"] == Value.string("Alice"))
                    #expect(user1["active"] == Value.boolean(true))

                    if case let .array(scores) = user1["scores"] {
                        #expect(scores.count == 3)
                        #expect(scores[0] == Value.double(95.5))
                    } else {
                        Issue.record("Expected scores array")
                    }
                } else {
                    Issue.record("Expected user1 object")
                }
            } else {
                Issue.record("Expected users array")
            }

            if case let .object(metadata) = decodedDict["metadata"] {
                #expect(metadata["total"] == Value.int(2))
                #expect(metadata["version"] == Value.double(1.1))
            } else {
                Issue.record("Expected metadata object")
            }

            #expect(decodedDict["settings"] == Value.null)
        } else {
            Issue.record("Expected root object")
        }
    }

    @Test("Edge cases and error handling")
    func edgeCases() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Test empty arrays and objects
        let emptyArray = Value.array([])
        let emptyArrayData = try encoder.encode(emptyArray)
        let decodedEmptyArray = try decoder.decode(Value.self, from: emptyArrayData)
        #expect(decodedEmptyArray == emptyArray)

        let emptyObject = Value.object([:])
        let emptyObjectData = try encoder.encode(emptyObject)
        let decodedEmptyObject = try decoder.decode(Value.self, from: emptyObjectData)
        #expect(decodedEmptyObject == emptyObject)

        // Test arrays with mixed types
        let mixedArray = Value.array([
            Value.string("text"),
            Value.int(42),
            Value.double(3.14),
            Value.boolean(true),
            Value.null,
            Value.array([Value.int(1), Value.int(2)]),
            Value.object(["nested": Value.string("value")]),
        ])
        let mixedArrayData = try encoder.encode(mixedArray)
        let decodedMixedArray = try decoder.decode(Value.self, from: mixedArrayData)
        #expect(decodedMixedArray == mixedArray)

        // Test objects with various key types (all should be strings in JSON)
        var objectWithVariousKeys = OrderedDictionary<String, Value>()
        objectWithVariousKeys["stringKey"] = Value.string("stringValue")
        objectWithVariousKeys["numberKey"] = Value.double(123.45)
        objectWithVariousKeys["booleanKey"] = Value.boolean(false)
        objectWithVariousKeys["nullKey"] = Value.null
        objectWithVariousKeys["arrayKey"] = Value.array([Value.int(1), Value.int(2)])
        objectWithVariousKeys["objectKey"] = Value.object(["nested": Value.string("nestedValue")])
    }

    @Test("JSON string escaping and unescaping")
    func jsonStringEscaping() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Test strings with special characters
        let specialString = Value.string("Hello \"World\" with\nnewlines\tand\ttabs")
        let specialStringData = try encoder.encode(specialString)
        let specialStringJSON = String(data: specialStringData, encoding: .utf8)!
        #expect(specialStringJSON.contains("\\\""))
        #expect(specialStringJSON.contains("\\n"))
        #expect(specialStringJSON.contains("\\t"))

        let decodedSpecialString = try decoder.decode(Value.self, from: specialStringData)
        #expect(decodedSpecialString == specialString)

        // Test strings with Unicode characters
        let unicodeString = Value.string("Hello 世界 🌍")
        let unicodeStringData = try encoder.encode(unicodeString)
        let decodedUnicodeString = try decoder.decode(Value.self, from: unicodeStringData)
        #expect(decodedUnicodeString == unicodeString)

        // Test empty string
        let emptyString = Value.string("")
        let emptyStringData = try encoder.encode(emptyString)
        let emptyStringJSON = String(data: emptyStringData, encoding: .utf8)!
        #expect(emptyStringJSON == "\"\"")

        let decodedEmptyString = try decoder.decode(Value.self, from: emptyStringData)
        #expect(decodedEmptyString == emptyString)
    }

    @Test("Error handling for invalid JSON")
    func invalidJsonHandling() throws {
        let decoder = JSONDecoder()

        // Test invalid JSON syntax
        let invalidJSONData = "{invalid json}".data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(Value.self, from: invalidJSONData)
        }

        // Test incomplete JSON
        let incompleteJSONData = "{\"key\":".data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(Value.self, from: incompleteJSONData)
        }

        // Test unsupported JSON types (like undefined in JSON)
        // Note: JSON doesn't have undefined, only null, so this should work
        let nullData = "null".data(using: .utf8)!
        let nullValue = try decoder.decode(Value.self, from: nullData)
        #expect(nullValue == Value.null)
    }

    // MARK: - Type Check Properties

    @Test("Type check properties")
    func typeCheckProperties() {
        #expect(Value.null.isNull)
        #expect(!Value.undefined.isNull)

        #expect(Value.undefined.isUndefined)
        #expect(!Value.null.isUndefined)

        #expect(Value.boolean(true).isBoolean)
        #expect(!Value.int(1).isBoolean)

        #expect(Value.int(42).isInt)
        #expect(!Value.double(42.0).isInt)

        #expect(Value.double(3.14).isDouble)
        #expect(!Value.int(3).isDouble)

        #expect(Value.string("hi").isString)
        #expect(!Value.int(0).isString)

        #expect(Value.array([]).isArray)
        #expect(!Value.string("[]").isArray)

        #expect(Value.object([:]).isObject)
        #expect(!Value.array([]).isObject)

        let fn = Value.function { _, _, _ in .null }
        #expect(fn.isFunction)
        #expect(!Value.null.isFunction)

        let macro = Value.macro(Macro(name: "m", parameters: [], defaults: [:], body: []))
        #expect(macro.isMacro)
        #expect(!fn.isMacro)

        #expect(Value.array([]).isIterable)
        #expect(Value.object([:]).isIterable)
        #expect(Value.string("abc").isIterable)
        #expect(!Value.int(1).isIterable)
        #expect(!Value.null.isIterable)
    }

    // MARK: - Arithmetic Operations

    @Test("Add operation")
    func addOperation() throws {
        #expect(try Value.int(2).add(with: .int(3)) == .int(5))
        #expect(try Value.double(1.5).add(with: .double(2.5)) == .double(4.0))
        #expect(try Value.int(1).add(with: .double(2.5)) == .double(3.5))
        #expect(try Value.string("hello").add(with: .string(" world")) == .string("hello world"))
        #expect(try Value.string("val:").add(with: .int(1)) == .string("val:1"))
        #expect(try Value.int(1).add(with: .string(":val")) == .string("1:val"))
        #expect(try Value.array([.int(1)]).add(with: .array([.int(2)])) == .array([.int(1), .int(2)]))
        #expect(throws: JinjaError.self) {
            _ = try Value.boolean(true).add(with: .int(1))
        }
    }

    @Test("Subtract operation")
    func subtractOperation() throws {
        #expect(try Value.int(5).subtract(by: .int(3)) == .int(2))
        #expect(try Value.double(5.5).subtract(by: .double(2.5)) == .double(3.0))
        #expect(try Value.int(5).subtract(by: .double(1.5)) == .double(3.5))
        #expect(try Value.double(5.5).subtract(by: .int(2)) == .double(3.5))
        #expect(throws: JinjaError.self) {
            _ = try Value.string("a").subtract(by: .string("b"))
        }
    }

    @Test("Multiply operation")
    func multiplyOperation() throws {
        #expect(try Value.int(3).multiply(by: .int(4)) == .int(12))
        #expect(try Value.double(2.5).multiply(by: .double(2.0)) == .double(5.0))
        #expect(try Value.string("ab").multiply(by: .int(3)) == .string("ababab"))
        #expect(try Value.int(2).multiply(by: .string("xy")) == .string("xyxy"))
        #expect(throws: JinjaError.self) {
            _ = try Value.string("a").multiply(by: .string("b"))
        }
    }

    @Test("Divide operation")
    func divideOperation() throws {
        #expect(try Value.int(10).divide(by: .int(4)) == .double(2.5))
        #expect(try Value.double(7.5).divide(by: .double(2.5)) == .double(3.0))
        #expect(throws: JinjaError.self) {
            _ = try Value.int(1).divide(by: .int(0))
        }
        #expect(throws: JinjaError.self) {
            _ = try Value.string("a").divide(by: .int(1))
        }
    }

    @Test("Modulo operation")
    func moduloOperation() throws {
        #expect(try Value.int(10).modulo(by: .int(3)) == .int(1))
        #expect(throws: JinjaError.self) {
            _ = try Value.int(10).modulo(by: .int(0))
        }
        #expect(throws: JinjaError.self) {
            _ = try Value.double(10.0).modulo(by: .double(3.0))
        }
    }

    @Test("Floor divide operation")
    func floorDivideOperation() throws {
        #expect(try Value.int(7).floorDivide(by: .int(2)) == .int(3))
        #expect(try Value.double(7.5).floorDivide(by: .double(2.0)) == .int(3))
        #expect(throws: JinjaError.self) {
            _ = try Value.int(1).floorDivide(by: .int(0))
        }
        #expect(throws: JinjaError.self) {
            _ = try Value.string("a").floorDivide(by: .int(1))
        }
    }

    @Test("Power operation")
    func powerOperation() throws {
        #expect(try Value.int(2).power(by: .int(3)) == .int(8))
        #expect(try Value.int(2).power(by: .int(-1)) == .double(0.5))
        #expect(try Value.double(2.0).power(by: .double(3.0)) == .double(8.0))
        #expect(throws: JinjaError.self) {
            _ = try Value.string("a").power(by: .int(2))
        }
    }

    // MARK: - Compare

    @Test("Compare operation")
    func compareOperation() throws {
        #expect(try Value.int(1).compare(to: .int(2)) == -1)
        #expect(try Value.int(2).compare(to: .int(2)) == 0)
        #expect(try Value.int(3).compare(to: .int(2)) == 1)
        #expect(try Value.string("a").compare(to: .string("b")) == -1)
        #expect(throws: JinjaError.self) {
            _ = try Value.int(1).compare(to: .string("a"))
        }
    }

    // MARK: - Containment

    @Test("isContained operation")
    func isContainedOperation() throws {
        #expect(try Value.int(2).isContained(in: .array([.int(1), .int(2), .int(3)])))
        #expect(try !Value.int(4).isContained(in: .array([.int(1), .int(2), .int(3)])))
        #expect(try Value.string("bc").isContained(in: .string("abcd")))
        #expect(try !Value.string("xy").isContained(in: .string("abcd")))
        #expect(try Value.string("key").isContained(in: .object(["key": .int(1)])))
        #expect(try !Value.string("missing").isContained(in: .object(["key": .int(1)])))
        #expect(try !Value.int(1).isContained(in: .undefined))
        #expect(try !Value.int(1).isContained(in: .null))
        #expect(throws: JinjaError.self) {
            _ = try Value.int(1).isContained(in: .int(42))
        }
    }

    // MARK: - Equivalence

    @Test("isEquivalent operation")
    func isEquivalentOperation() {
        #expect(Value.int(3).isEquivalent(to: .double(3.0)))
        #expect(!Value.int(3).isEquivalent(to: .double(3.1)))
        #expect(Value.array([.int(1), .int(2)]).isEquivalent(to: .array([.int(1), .int(2)])))
        #expect(!Value.array([.int(1)]).isEquivalent(to: .array([.int(2)])))
        #expect(Value.object(["a": .int(1)]).isEquivalent(to: .object(["a": .int(1)])))
        #expect(!Value.object(["a": .int(1)]).isEquivalent(to: .object(["b": .int(1)])))

        let m = Macro(name: "test", parameters: [], defaults: [:], body: [])
        #expect(Value.macro(m).isEquivalent(to: .macro(m)))

        let fn = Value.function { _, _, _ in .null }
        #expect(!fn.isEquivalent(to: fn))
    }

    // MARK: - Concatenate

    @Test("Concatenate operation")
    func concatenateOperation() throws {
        #expect(try Value.string("a").concatenate(with: .string("b")) == .string("ab"))
        #expect(try Value.string("x").concatenate(with: .int(1)) == .string("x1"))
        #expect(try Value.int(1).concatenate(with: .string("x")) == .string("1x"))
        #expect(throws: JinjaError.self) {
            _ = try Value.int(1).concatenate(with: .int(2))
        }
    }

    // MARK: - Description for Function and Macro

    @Test("Function and macro description")
    func functionMacroDescription() {
        let fn = Value.function { _, _, _ in .null }
        #expect(fn.description == "[Function]")

        let m = Macro(name: "greet", parameters: [], defaults: [:], body: [])
        #expect(Value.macro(m).description.contains("greet"))
    }

    // MARK: - isTruthy for Function and Macro

    @Test("isTruthy for function and macro")
    func isTruthyFunctionMacro() {
        let fn = Value.function { _, _, _ in .null }
        #expect(fn.isTruthy)

        let m = Macro(name: "test", parameters: [], defaults: [:], body: [])
        #expect(Value.macro(m).isTruthy)
    }

    // MARK: - Init from Macro

    @Test("Init from Macro via any")
    func initFromMacro() throws {
        let m = Macro(name: "test", parameters: [], defaults: [:], body: [])
        let value = try Value(any: m)
        #expect(value == .macro(m))
        #expect(value.isMacro)
    }

    // MARK: - Mixed Numeric Arithmetic

    @Test("Double + Int addition")
    func doubleAddInt() throws {
        #expect(try Value.double(1.5).add(with: .int(2)) == .double(3.5))
    }

    @Test("Int * Double multiplication")
    func intMultiplyDouble() throws {
        #expect(try Value.int(3).multiply(by: .double(2.5)) == .double(7.5))
    }

    @Test("Double * Int multiplication")
    func doubleMultiplyInt() throws {
        #expect(try Value.double(2.5).multiply(by: .int(3)) == .double(7.5))
    }

    @Test("Int / Double division")
    func intDivideDouble() throws {
        #expect(try Value.int(5).divide(by: .double(2.0)) == .double(2.5))
    }

    @Test("Double / Int division")
    func doubleDivideInt() throws {
        #expect(try Value.double(7.5).divide(by: .int(3)) == .double(2.5))
    }

    @Test("Double / Double division by zero throws")
    func doubleDivideDoubleByZero() throws {
        #expect(throws: JinjaError.self) {
            _ = try Value.double(1.0).divide(by: .double(0.0))
        }
    }

    @Test("Int / Double division by zero throws")
    func intDivideDoubleByZero() throws {
        #expect(throws: JinjaError.self) {
            _ = try Value.int(1).divide(by: .double(0.0))
        }
    }

    @Test("Double / Int division by zero throws")
    func doubleDivideIntByZero() throws {
        #expect(throws: JinjaError.self) {
            _ = try Value.double(1.0).divide(by: .int(0))
        }
    }

    // MARK: - Floor Division Mixed Types

    @Test("Double floor divide double")
    func doubleFloorDivideDouble() throws {
        #expect(try Value.double(7.5).floorDivide(by: .double(2.0)) == .int(3))
    }

    @Test("Int floor divide double")
    func intFloorDivideDouble() throws {
        #expect(try Value.int(7).floorDivide(by: .double(2.0)) == .int(3))
    }

    // MARK: - Compare Mixed Types

    @Test("Double compare Int")
    func doubleCompareInt() throws {
        #expect(try Value.double(3.5).compare(to: .int(3)) == 1)
        #expect(try Value.double(3.0).compare(to: .int(3)) == 0)
        #expect(try Value.double(2.5).compare(to: .int(3)) == -1)
    }

    @Test("Int compare Double")
    func intCompareDouble() throws {
        #expect(try Value.int(4).compare(to: .double(3.5)) == 1)
        #expect(try Value.int(3).compare(to: .double(3.0)) == 0)
        #expect(try Value.int(2).compare(to: .double(3.5)) == -1)
    }

    // MARK: - isEquivalent edge cases

    @Test("isEquivalent double/int")
    func isEquivalentDoubleInt() {
        #expect(Value.double(3.0).isEquivalent(to: .int(3)))
        #expect(!Value.double(3.1).isEquivalent(to: .int(3)))
    }

    @Test("isEquivalent arrays different length")
    func isEquivalentArraysDifferentLength() {
        #expect(!Value.array([.int(1), .int(2)]).isEquivalent(to: .array([.int(1)])))
    }

    @Test("isEquivalent objects different keys")
    func isEquivalentObjectsDifferentKeys() {
        #expect(!Value.object(["a": .int(1)]).isEquivalent(to: .object(["b": .int(1)])))
    }

    @Test("isEquivalent objects different values")
    func isEquivalentObjectsDifferentValues() {
        #expect(!Value.object(["a": .int(1)]).isEquivalent(to: .object(["a": .int(2)])))
    }

    // MARK: - Encodable macro

    @Test("Encodable macro")
    func encodableMacro() throws {
        let m = Macro(name: "test", parameters: [], defaults: [:], body: [])
        let encoder = JSONEncoder()
        let data = try encoder.encode(Value.macro(m))
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("test"))
    }

    // MARK: - Description for array with strings

    @Test("Array with strings uses single quotes")
    func arrayWithStringsDescription() {
        let value = Value.array([.string("hello"), .string("world")])
        #expect(value.description == "['hello', 'world']")
    }

    @Test("Array with mixed types description")
    func arrayMixedDescription() {
        let value = Value.array([.string("a"), .int(1), .boolean(true)])
        #expect(value.description == "['a', 1, true]")
    }

    // MARK: - Hash for various types

    @Test("Hash for double")
    func hashDouble() {
        var hasher1 = Hasher()
        Value.double(3.14).hash(into: &hasher1)
        var hasher2 = Hasher()
        Value.double(3.14).hash(into: &hasher2)
        #expect(hasher1.finalize() == hasher2.finalize())
    }

    @Test("Hash for array")
    func hashArray() {
        var hasher = Hasher()
        Value.array([.int(1), .int(2)]).hash(into: &hasher)
        _ = hasher.finalize()
    }

    @Test("Hash for object")
    func hashObject() {
        var hasher = Hasher()
        Value.object(["a": .int(1)]).hash(into: &hasher)
        _ = hasher.finalize()
    }

    @Test("Hash for function")
    func hashFunction() {
        var hasher = Hasher()
        Value.function { _, _, _ in .null }.hash(into: &hasher)
        _ = hasher.finalize()
    }

    @Test("Hash for undefined")
    func hashUndefined() {
        var hasher = Hasher()
        Value.undefined.hash(into: &hasher)
        _ = hasher.finalize()
    }

    @Test("Hash for macro")
    func hashMacro() {
        let m = Macro(name: "test", parameters: [], defaults: [:], body: [])
        var hasher = Hasher()
        Value.macro(m).hash(into: &hasher)
        _ = hasher.finalize()
    }
}
