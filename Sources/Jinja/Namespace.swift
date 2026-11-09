import Foundation

/// Namespace metadata stays inside the existing object representation.
/// The marker's payload cannot be constructed by a template or a decoded macro.
/// Attributes live in the payload so that every string remains a valid name.
/// This preserves the public Value cases and the object case's associated type.
/// Swift callers that unpack the object can still see its marker entry.
/// Copies retain identity and use the existing value-based assignment semantics.
struct Namespace: Hashable, Sendable {
    private static let markerKey = ObjectKey.string("\0jinja.namespace")

    private let identity = UUID()
    var attributes: OrderedDictionary<ObjectKey, Value>

    var value: Value {
        var marker = Macro(name: "", parameters: [], defaults: [:], body: [])
        marker.namespace = self
        return .object([Self.markerKey: .macro(marker)])
    }

    static func get(_ object: OrderedDictionary<ObjectKey, Value>) -> Namespace? {
        guard object.count == 1, case let .macro(marker) = object[markerKey] else {
            return nil
        }
        return marker.namespace
    }

    static func requireMapping(_ object: OrderedDictionary<ObjectKey, Value>) throws {
        guard get(object) == nil else {
            throw JinjaError.runtime("Namespace is not a mapping or iterable")
        }
    }

    static func == (lhs: Namespace, rhs: Namespace) -> Bool {
        lhs.identity == rhs.identity
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
    }
}

extension Value {
    var namespace: Namespace? {
        guard case let .object(object) = self else { return nil }
        return Namespace.get(object)
    }
}
