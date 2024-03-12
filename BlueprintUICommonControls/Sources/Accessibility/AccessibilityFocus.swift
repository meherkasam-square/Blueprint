import BlueprintUI
import UIKit


/// Posts a `UIAccessibility.Notification` with the wrapped element as the argument.
public struct AccessibilityFocus: Element {

    /// The element to be posted.
    public var wrapped: Element

    /// If the `UIAccessibility.Notification` to post.
    /// Only `.layoutChanged` and  `.screenChanged` notifications will focus the supplied element. `.Announcement`notifications can ususally be posted directly.
    public var notification: UIAccessibility.Notification = .layoutChanged

    public var trigger: AccessibilityFocusTrigger

    /// Creates a new `AccessibilityNotifier` wrapping the provided element.
    public init(
        notification: UIAccessibility.Notification,
        trigger: AccessibilityFocusTrigger,
        wrapping element: Element
    ) {
        self.notification = notification
        self.trigger = trigger
        wrapped = element
    }

    //
    // MARK: Element
    //

    public var content: ElementContent {
        ElementContent(child: wrapped)
    }

    public func backingViewDescription(with context: ViewDescriptionContext) -> ViewDescription? {
        AccessibilityNotifierView.describe { config in
            config.apply { view in
                view.apply(model: self)
            }
        }
    }
}

public final class AccessibilityFocusTrigger {
    /// Create a new trigger, not yet bound to any view.
    public init() {}

    /// The action to be invoked on trigger, which will be set by a backing view.
    fileprivate var focusAction: (() -> Void)?

    /// Posts the notification from the view bound to this trigger.
    public func focus() {
        focusAction?()
    }
}

extension Element {
    /// Allows the posting of an accessibility notification with the wrapped view is the argument.
    public func accessibilityFocus(
        notification: UIAccessibility.Notification = .layoutChanged,
        trigger: AccessibilityFocusTrigger
    ) -> AccessibilityFocus {
        AccessibilityFocus(notification: notification, trigger: trigger, wrapping: self)
    }
}


private class AccessibilityNotifierView: UIView {
    private var blueprintView = BlueprintView()
    private var notification: UIAccessibility.Notification?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        addSubview(blueprintView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blueprintView.frame = bounds
    }

    func apply(model: AccessibilityFocus) {
        blueprintView.element = model.wrapped
        notification = model.notification
        model.trigger.focusAction = { [weak self] in
            guard let notification = self?.notification else { return }
            UIAccessibility.post(notification: notification, argument: self)
        }
    }
}
