import Foundation

/// Controls the layout system that Blueprint uses to lay out elements.
///
/// Blueprint supports multiple layout systems. Each is expected to produce the same result, but
/// some may have different performance profiles or special requirements.
///
/// You can change the layout system used by setting the ``BlueprintView/layoutMode`` property, but
/// generally you should use the ``default`` option.
///
/// Changing the default will cause all instances of ``BlueprintView`` to be invalidated, and re-
/// render their contents.
///
public enum LayoutMode: Equatable {
    public static var `default`: Self = .legacy {
        didSet {
            guard oldValue != .default else { return }
            NotificationCenter
                .default
                .post(name: .defaultLayoutModeChanged, object: nil)
        }
    }

    /// The "standard" layout system.
    case legacy

    /// A newer layout system with some optimizations made possible by ensuring elements adhere
    /// to a certain contract for behavior.
    case caffeinated(options: LayoutOptions = .default)

    /// A newer layout system with some optimizations made possible by ensuring elements adhere
    /// to a certain contract for behavior.
    public static let caffeinated = Self.caffeinated()
}

extension Notification.Name {
    static let defaultLayoutModeChanged: Self = .init(
        "com.squareup.blueprint.defaultLayoutModeChanged"
    )
}
