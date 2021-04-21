import UIKit

/// `StackChild` is a wrapper which allows an element to define its StackLayout traits and Keys.
/// This struct is particularly useful when working with `@StackElementBuilder`.
/// By default, elements will default to a nil key and the default `StackLayout.Traits` initializer.
/// `@StackElementBuilder` will check every child to see if it can be type cast to a `StackChild`
/// and then pull of the given traits and key and then apply those to the stack
public struct StackChild: ProxyElement {
    public var traits: StackLayout.Traits
    public var key: AnyHashable?
    private let wrappedElement: Element

    public init(
        wrappedElement: Element,
        traits: StackLayout.Traits = .init(),
        key: AnyHashable? = nil
    ) {
        self.wrappedElement = wrappedElement
        self.traits = traits
        self.key = key
    }
    
    public init(
        wrappedElement: Element,
        growPriority: CGFloat = 1.0,
        shrinkPriority: CGFloat = 1.0,
        alignmentGuide: ((ElementDimensions) -> CGFloat)? = nil,
        key: AnyHashable? = nil
    ) {
        self.init(
            wrappedElement: wrappedElement,
            traits: .init(
                growPriority: growPriority,
                shrinkPriority: shrinkPriority,
                alignmentGuide: alignmentGuide.map(StackLayout.AlignmentGuide.init)
            ),
            key: key
        )
    }

    // Simply wraps the given element.
    public var elementRepresentation: Element { wrappedElement }
}

extension Element {
    
    /// Wraps an element with a `StackChild` in order to customize `StackLayout.Traits` and the key.
    /// - Parameters:
    ///   - growPriority: Controls the amount of extra space distributed to this child during underflow.
    ///   - shrinkPriority: Controls the amount of space allowed for this child during overflow.
    ///   - alignmentGuide: Allows for custom alignment of a child along the cross axis.
    ///   - key: A key used to disambiguate children between subsequent updates of the view
    ///     hierarchy.
    /// - Returns: A wrapped element with additional layout information for the `StackElement`.
    public func stackChild(
        growPriority: CGFloat = 1.0,
        shrinkPriority: CGFloat = 1.0,
        alignmentGuide: ((ElementDimensions) -> CGFloat)? = nil,
        key: AnyHashable? = nil
    ) -> StackChild {
        .init(
            wrappedElement: self,
            growPriority: growPriority,
            shrinkPriority: shrinkPriority,
            alignmentGuide: alignmentGuide, key: key
        )
    }
    
    /// Wraps an element with a `StackChild` in order to customize `StackLayout.Traits` and the key.
    /// - Parameters:
    ///   - traits: Contains traits that affect the layout of individual children in the stack.
    ///   - key: A key used to disambiguate children between subsequent updates of the view
    ///     hierarchy.
    /// - Returns: A wrapped element with additional layout information for the `StackElement`.
    public func stackChild(traits: StackLayout.Traits = .init(), key: AnyHashable? = nil) -> StackChild {
        .init(wrappedElement: self, traits: traits, key: key)
    }
}


extension StackElement {
    /// Initializer using result builder to declaritively build up a stack.
    /// - Parameters:
    ///   - children: A block containing all elements to be included in the stack.
    ///   - configure: A closure used to modify the stack.
    /// - Note: If element is a StackChild, then traits and key will be pulled from the element, otherwise defaults are passed through.
    public init(@Builder<Element> elements: () -> [Element], configure: (inout Self) -> Void = { _ in }) {
        self.init()
        self.children = elements().map { element in
            if let stackChild = element as? StackChild {
                return (stackChild, stackChild.traits, stackChild.key)
            } else {
                return (element, StackLayout.Traits(), nil)
            }
        }
        configure(&self)
    }
    
    /// Initializes stack transforming an array of some item into an array of elements.
    /// - Parameters:
    ///   - items: The array of items to transform.
    ///   - transform: Closure to be applied to each item `T` which transforms that item into an `Element`.
    ///   - configure: A closure used to modify the stack.
    public init<T>(_ items: [T], transform: (T) -> Element, configure: (inout Self) -> Void = { _ in }) {
        self.init()
        children = items.map(transform).map { element in
            if let stackChild = element as? StackChild {
                return (stackChild, stackChild.traits, stackChild.key)
            } else {
                return (element, StackLayout.Traits(), nil)
            }
        }
        configure(&self)
    }
}
