import BlueprintUI
import UIKit

/// Acts as an accessibility container for any accessible subviews.
///
/// Accessible subviews are found using the following algorithm:
///
/// Recurse subviews until a view is found that either
/// - has`isAccessibilityElement` set to `true` or
/// - returns a non-nil value from `accessibilityElements` (i.e., is a container itself)
///
/// If an accessibility element is found, we add it to the `accessibilityElements`
/// and terminate the search down that branch. If a container is found,
/// the elements returned from the container are added to the `accessibilityElements`
/// and the search down that branch is also terminated.
public struct AccessibilityContainer: Element, KeyPathComparableElement {

    /// An optional `accessibilityIdentifier` to give the container. Defaults to `nil`.
    public var identifier: String?
    public var wrapped: Element

    /// Creates a new `AccessibilityContainer` wrapping the provided element.
    public init(identifier: String? = nil, wrapping element: Element) {
        self.identifier = identifier
        self.wrapped = element
    }

    //
    // MARK: Element
    //

    public var content: ElementContent {
        ElementContent(child: wrapped)
    }

    public func backingViewDescription(with context: ViewDescriptionContext) -> ViewDescription? {
        AccessibilityContainerView.describe { config in
            config[\.accessibilityIdentifier] = identifier
        }
    }
    
    public static let isEquivalent = IsEquivalent<AccessibilityContainer> {
        $0.add(\.wrapped)
    }
}

public extension Element {

    /// Acts as an accessibility container for any subviews
    /// where `isAccessibilityElement == true`.
    func accessibilityContainer(identifier: String? = nil) -> Element {
        AccessibilityContainer(identifier: identifier, wrapping: self)
    }
}

extension AccessibilityContainer {
    private final class AccessibilityContainerView: UIView {
        override var accessibilityElements: [Any]? {
            get { recursiveAccessibleSubviews() }
            set { fatalError("This property is not settable") }
        }
    }
}

extension UIView {
    func recursiveAccessibleSubviews() -> [Any] {
        subviews.flatMap { subview -> [Any] in
            if let accessibilityElements = subview.accessibilityElements {
                return accessibilityElements
            } else if subview.isAccessibilityElement {
                return [subview]
            } else {
                return subview.recursiveAccessibleSubviews()
            }
        }
    }
}
