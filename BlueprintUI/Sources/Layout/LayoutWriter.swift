//
//  LayoutWriter.swift
//  BlueprintUI
//
//  Created by Kyle Van Essen on 10/7/20.
//

import UIKit


/// A parent element which allows arbitrary, custom layout and positioning of its children.
///
/// Instead of creating a custom `Element` with a custom `Layout`, you might use
/// this element to create a customized layout in a more lightweight way.
///
/// ```
/// LayoutWriter { context, layout in
///     layout.add(with: myFrame, child: myElement)
///     layout.add(with: myOtherFrame, child: myOtherElement)
///
///     layout.sizing = .unionOfChildren
/// }
/// ```
public struct LayoutWriter: Element {

    //
    // MARK: Initialization
    //

    /// Creates a new instance of the LayoutWriter with the custom layout provided by the builder.
    ///
    /// The parameters to the closure are the `Context`, which provides information about
    /// the environment and sizing of the layout, and the `Builder` itself, which you use to
    /// add child elements to the layout.
    public init(_ build: @escaping Build) {
        self.build = build
    }

    /// The builder type passed to the `LayoutWriter` initializer.
    public typealias Build = (Context, inout Builder) -> Void

    /// The builder used to create the custom layout.
    public let build: Build

    //
    // MARK: Element
    //

    public var content: ElementContent {
        ElementContent { size, env -> Element in
            var builder = Builder()
            self.build(Context(size: size), &builder)

            return Content(builder: builder)
        }
    }

    public func backingViewDescription(with context: ViewDescriptionContext) -> ViewDescription? {
        nil
    }
}


extension LayoutWriter {

    /// The builder is the primary surface area you interact with when using a `LayoutWriter`.
    ///
    /// It provides you the ability to manage the sizing and measurement of the final layout,
    /// alongside methods to add and manage the children of the layout.
    public struct Builder {

        //
        // MARK: Managing Sizing
        //

        /// How the size of the layout should be calculated. Defaults to `.unionOfChildren`,
        /// which means the size will be big enough to contain the frames of all contained children.
        public var sizing: Sizing = .unionOfChildren

        //
        // MARK: Managing Children
        //

        /// The children of the custom layout, which specifies the child element and its frame.
        ///
        /// Note
        /// ----
        /// You rarely need to access this property directly. Instead, add children via
        /// the various provided `add(...)` methods. However, if you're `map`-ing over an array
        /// or other collection of content, using this property directly is useful.
        ///
        public var children: [Child] = []

        /// Adds a new child element to the layout with the provided frame and optional key.
        public mutating func add(
            with frame: CGRect,
            key: AnyHashable? = nil,
            child: Element
        ) {
            children.append(.init(frame: frame, key: key, element: child))
        }

        /// Adds a new child element to the layout.
        public mutating func add(_ child: Child) {
            children.append(child)
        }

        /// Enumerates each of the children, allowing you to modify them in place,
        /// eg to align them all along a common alignment axis or to set a uniform size.
        public mutating func modifyEach(using change: (inout Child) -> Void) {
            children = children.map {
                var updated = $0
                change(&updated)
                return updated
            }
        }
    }

    /// Provides the relevant information about the context in which the layout is occurring.
    public struct Context {

        /// The size constraint the layout is occurring in.
        public var size: SizeConstraint
    }

    /// Controls the sizing calculation of the custom layout.
    public enum Sizing: Equatable {

        /// Ensures that the final size of element is large enough to fit all children, starting from (0,0).
        ///
        /// Negative origins of rects are not considered in this calculation. If you have the following layout:
        /// ```
        ///  ┌──────┐
        ///  │      ├─────────┐
        ///  │      │*********│
        ///  └─┬────┘**┌──────┤
        ///    │*******│      │
        ///    │*******│      │
        /// ┌──┴───┐***│      │
        /// │      │***│      │
        /// │      │***└──────┤
        /// └──────┴──────────┘
        /// ```
        /// The large rect will be the calculated size / bounds of the layout, starting at (0,0). Any rects with
        /// negative origins will overhang the layout to the top or left, respectively.
        case unionOfChildren

        /// Fixes the layout size to the provided size. Children are positioned within this size, starting at (0,0)
        /// Any rects with negative origins will overhang the layout to the top or left, respectively.
        case fixed(CGSize)

        /// Measures the size of the content within the builder.
        func measure(with builder: Builder) -> CGSize {
            switch self {
            case .unionOfChildren:
                return CGSize(
                    width: builder.children.reduce(0.0) { width, child in
                        max(width, child.frame.maxX)
                    },
                    height: builder.children.reduce(0.0) { height, child in
                        max(height, child.frame.maxY)
                    }
                )
            case .fixed(let size):
                return size
            }
        }
    }

    /// A child of the custom layout, providing its frame and element.
    public struct Child {

        /// The frame of the element in the coordinate space of the custom layout.
        public var frame: CGRect

        /// The key to use to disambiguate this element.
        public var key: AnyHashable?

        /// The element to be displayed.
        public var element: Element

        /// Creates a new child element.
        public init(
            frame: CGRect,
            key: AnyHashable? = nil,
            element: Element
        ) {
            self.frame = frame
            self.key = key
            self.element = element
        }
    }
}


extension LayoutWriter {

    private struct Content: Element {
        var builder: Builder

        // MARK: Element

        var content: ElementContent {
            ElementContent(layout: Layout(builder: builder)) { builder in
                for child in self.builder.children {
                    builder.add(traits: child.frame, key: child.key, element: child.element)
                }
            }
        }

        func backingViewDescription(with context: ViewDescriptionContext) -> ViewDescription? {
            nil
        }

        // MARK: Layout

        private struct Layout: BlueprintUI.Layout, SPLayout {
            static let defaultTraits: CGRect = .zero

            var builder: Builder

            func measure(in constraint: SizeConstraint, items: [(traits: CGRect, content: Measurable)]) -> CGSize {
                builder.sizing.measure(with: builder)
            }

            func layout(size: CGSize, items: [(traits: CGRect, content: Measurable)]) -> [LayoutAttributes] {
                builder.children.map { child in
                    .init(frame: child.frame)
                }
            }

            func layout(in context: SPLayoutContext, children: [SPLayoutChild]) -> SPLayoutAttributes {
                let options = SPLayoutOptions(mode: .init(horizontal: .fill, vertical: .fill))
                let size = builder.sizing.measure(with: builder)

                for child in children {
                    _ = child.layoutable.layout(
                        in: child.traits.size
//                        options: options
                    )
                }

                return SPLayoutAttributes(
                    size: size,
                    childPositions: children.map { $0.traits.origin }
                )
            }
        }
    }
}

