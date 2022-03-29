
import Foundation

/// Types conforming to this protocol can be used as keys in an `Environment`.
///
/// Using a type as the key allows us to strongly type each value, with the
/// key's `EnvironmentKey.Value` associated value.
///
/// ## Example
///
/// Usually a key is implemented with an uninhabited type, such an empty enum.
///
///     enum WidgetCountKey: EnvironmentKey {
///         static let defaultValue: Int = 0
///     }
///
/// You can write a small extension on `Environment` to make it easier to use your key.
///
///     extension Environment {
///         var widgetCount: Int {
///             get { self[WidgetCountKey.self] }
///             set { self[WidgetCountKey.self] = newValue }
///         }
///     }
public protocol EnvironmentKey {
    /// The type of value stored by this key.
    associatedtype Value

    /// The default value that will be vended by an `Environment` for this key if no other value
    /// has been set.
    static var defaultValue: Self.Value { get }

    static func equals(_ lhs: Value, _ rhs: Value) -> Bool
}


extension EnvironmentKey where Value: Equatable {

    public static func equals(_ lhs: Value, _ rhs: Value) -> Bool {
        lhs == rhs
    }
}


extension EnvironmentKey where Value: AnyObject {

    public static func equals(_ lhs: Value, _ rhs: Value) -> Bool {
        lhs === rhs
    }
}

extension EnvironmentKey where Value: NSObject {

    public static func equals(_ lhs: Value, _ rhs: Value) -> Bool {
        lhs.isEqual(rhs)
    }
}


extension EnvironmentKey {

    static func anyEquals(_ lhs: Any?, _ rhs: Any?) -> Bool {

        if lhs == nil && rhs == nil { return true }

        guard
            let lhs = lhs as? Value,
            let rhs = rhs as? Value
        else {
            return false
        }

        return Self.equals(lhs, rhs)
    }
}
