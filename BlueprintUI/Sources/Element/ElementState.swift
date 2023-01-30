//
//  ElementState.swift
//  BlueprintUI
//
//  Created by Kyle Van Essen on 6/24/21.
//

import Foundation
import UIKit


/// The root node in an `ElementState` tree, which is used by `BlueprintView`
/// to maintain state across multiple layout passes.
final class ElementStateTree {

    /// The root element in the tree. Nil if there is no element.
    private(set) var root: ElementState?

    /// A signpost token used for logging signposts to `os_log`.
    private let signpostRef: SignpostToken = .init()

    /// An optional delegate to be informed about the layout process.
    weak var delegate: ElementStateTreeDelegate? = nil {
        didSet {
            guard oldValue !== delegate else { return }

            root?.recursiveForEach {
                $0.delegate = delegate
            }
        }
    }

    /// A human readable name that represents the tree. Useful for debugging.
    var name: String {
        didSet {
            guard oldValue == name else { return }

            root?.recursiveForEach {
                $0.name = name
            }
        }
    }

    init(name: String) {
        self.name = name
    }

    /// Updates or replaces the root node depending on the type of the new element.
    ///
    /// This method will also remove any `ElementState` for elements no longer present in the element tree.
    func performUpdate<Output>(
        with element: Element,
        in environment: Environment,
        updates: (ElementState) -> Output
    ) -> (ElementState, Output) {
        func makeRoot(with element: Element) -> ElementState {

            let new = ElementState(
                parent: nil,
                delegate: delegate,
                identifier: .identifierFor(singleChild: element),
                element: element,
                signpostRef: signpostRef,
                name: name
            )

            root = new

            return new
        }

        if let root = root {

            if type(of: root.element.latest) == type(of: element) {

                root.prepareForLayout()

                root.update(with: element, in: environment, identifier: root.identifier)

                delegate.ifDebug {
                    $0.tree(self, didUpdateRootState: root)
                }

                let output = updates(root)

                root.finishedLayout()

                return (root, output)
            } else {
                let new = makeRoot(with: element)

                delegate.ifDebug {
                    $0.tree(self, didReplaceRootState: root, with: new)
                }

                let output = updates(new)

                root.finishedLayout()

                return (new, output)
            }
        } else {
            let new = makeRoot(with: element)

            delegate.ifDebug {
                $0.tree(self, didSetupRootState: new)
            }

            let output = updates(new)

            new.finishedLayout()

            return (new, output)
        }
    }

    func teardownRootElement() -> ElementState? {

        guard let old = root else { return nil }

        root = nil

        delegate.ifDebug {
            $0.tree(self, didTeardownRootState: old)
        }

        return old
    }
}


/// Represents the live, on screen state for a given element in the element tree.
///
/// `ElementState` is updated with the newest state of its backing `Element`
/// during the layout pass, and retains cached information such as measurements
/// and layouts either to the end of the layout pass, or until the equivalency of the `Element`
/// changes, for comparable elements.
final class ElementState {

    /// The parent element that owns this element.
    private(set) weak var parent: ElementState?

    fileprivate(set) weak var delegate: ElementStateTreeDelegate? = nil

    /// The identifier of the element. Eg, `Inset.1` or `Inset.1.Key`.
    let identifier: ElementIdentifier

    /// The signpost ref used when logging to `os_log`.
    let signpostRef: AnyObject

    /// The name of the owning tree. Useful for debugging.
    var name: String

    /// The element represented by this object.
    /// This value is a reference type – the inner element value
    /// will change after updates.
    let element: ElementState.LatestElement

    /// How and if the element should be compared during updates.
    let comparability: Comparability

    /// If the element enables any caching. Dynamic elements such as
    /// `GeometryReader` or `EnvironmentReader` will disable caching.
    let isCachingEnabled: Bool

    /// If the node has been visited this layout cycle.
    ///
    /// If this value is `false`, at the end of a layout cycle, the
    /// `ElementState` will be torn down; indicating it  is no longer part
    /// of the element tree.
    private(set) var wasVisited: Bool

    /// If the node has been updated this layout cycle.
    ///
    /// This is used to ensure we only `update` the `ElementState`
    /// for an `Element` once per layout cycle. There are some exceptions
    /// to this, for example a dynamic element such as a `GeometryReader` or
    /// `EnvironmentReader` will update this child nodes on each build of its content.
    private(set) var hasUpdated: Bool

    /// If the node has updated its children with their latest `ElementContent`
    /// while returning a cached layout.
    private(set) var hasUpdatedChildrenDuringLayout: Bool

    /// The cached measurements for the current node.
    /// Measurements are cached by a `SizeConstraint` key, meaning that
    /// there can be multiple cached measurements for the same element.
    private var measurements: [SizeConstraint: CachedMeasurement] = [:]

    /// The cached layouts for the current node.
    /// Layouts are cached by a `CGSize` key, meaning that
    /// we can preserve multiple layouts if the containing element or containing
    /// view's size changes, eg when rotating from portait to landscape.
    private var layouts: [CGSize: CachedLayout] = [:]

    /// The kind of cache we're storing in the state. This is only used for debugging
    /// purposes to differentiate between regular state and state that is only used for
    /// measurement caching
    private(set) var kind: Kind

    /// The children of the `ElementState`, cached by element identifier.
    private(set) var children: [ElementIdentifier: ElementState] = [:]

    /// Indicates the comparability behavior of the element.
    /// See each case for details on behavior.
    enum Comparability: Equatable {
        /// The element is not comparable, and it is not the child of a comparable element.
        ///
        /// ### Measurement Pass
        /// No measurements will be cached. Each render cycle will cause a new measurement pass.
        ///
        /// ### Layout Pass
        /// No layouts will be cached. Each render cycle will cause a new layout pass.
        case notComparable

        /// The element is comparable itself; it conforms to `ComparableElement`.
        ///
        /// ### Measurement Pass
        /// Measurements will be cached across render cycles if `isEquivalent` returns `true`,
        /// and the `Environment` dependencies for the measurement are equivalent.
        ///
        /// ### Layout Pass
        /// Layouts will be cached across render cycles if `isEquivalent` returns `true`,
        /// and the `Environment` dependencies for the measurement are equivalent.
        case comparableElement

        /// The element is the child of a `ComparableElement`, meaning its comparability
        /// is determined by the comparability of that parent element. All direct and indirect
        /// children of a `ComparableElement` are `.childOfComparableElement`,
        /// meaning every element below `MyComparableElement` in the below example:
        ///
        /// ```
        ///  MyComparableElement
        ///    Inset
        ///      Aligned
        ///        ChildElement 📍 // You are here
        /// ```
        ///
        /// ### Measurement Pass
        /// Measurements will be cached across render cycles if `isEquivalent` for
        /// the parent `ComparableElement` returns `true`, and
        /// the `Environment` dependencies for the measurement are equivalent.
        ///
        /// ### Layout Pass
        /// Layouts for this inner child element are not cached. Because layouts are a tree;
        /// the parent `ComparableElement` will cache its layout tree. Our layout
        /// function will not even be invoked as long as the parent remains `isEquivalent`.
        case childOfComparableElement

        /// If the element is either directly comparable, or the child of a `ComparableElement`.
        var isComparable: Bool {
            switch self {
            case .notComparable: return false
            case .comparableElement: return true
            case .childOfComparableElement: return true
            }
        }
    }

    /// The kind of cache to be stored in this `ElementState`
    enum Kind {

        /// Only measurement information is available to cache
        /// in this state
        case measurementOnly

        /// All cachable information is stored in this state
        case regular

        init(parent: ElementState?, content: ElementContent) {
            if let parent {
                if parent.elementContent.isMeasurementOnlyNode || content.isMeasurementOnlyNode {
                    self = .measurementOnly
                } else {
                    self = .regular
                }
            } else {
                if content.isMeasurementOnlyNode {
                    self = .measurementOnly
                } else {
                    self = .regular
                }
            }
        }
    }

    /// Creates a new `ElementState` instance.
    init(
        parent: ElementState?,
        delegate: ElementStateTreeDelegate?,
        identifier: ElementIdentifier,
        element: Element,
        signpostRef: AnyObject,
        name: String
    ) {
        self.parent = parent
        self.delegate = delegate
        self.identifier = identifier
        self.element = .init(element)

        let elementContent = self.element.latest.content

        cachedContent = elementContent

        kind = .init(parent: parent, content: elementContent)

        if element is AnyComparableElement {
            comparability = .comparableElement
        } else if let parent = parent {
            switch parent.comparability {
            case .notComparable:
                comparability = .notComparable
            case .comparableElement, .childOfComparableElement:
                comparability = .childOfComparableElement
            }
        } else {
            comparability = .notComparable
        }

        isCachingEnabled = elementContent.dynamicallyGeneratesContent == false

        self.signpostRef = signpostRef
        self.name = name

        wasVisited = true
        hasUpdated = true
        hasUpdatedChildrenDuringLayout = true
    }

    /// Assigned once per layout cycle, this value represents the
    /// `Element.content` value from the represented element.
    /// This value is cached to improve performance (fewer allocations and
    /// less repeated content building), as well as improves debuggability.
    private var cachedContent: ElementContent?

    /// Allows the layout system in `ElementContent` to access the `ElementContent`
    /// of the element, returning a cached version after the first access during a layout cycle if
    /// caching is allowed.
    ///
    /// ### Note
    /// Caching is disabled for elements like `GeometryReader` and `EnvironmentReader`,
    /// as these may arbitrarily change the returned children based on layout size, environment
    /// contents, etc.
    var elementContent: ElementContent {
        if let cachedContent = cachedContent {
            return cachedContent
        } else {
            let content = element.latest.content

            /// TODO: Can we cache this? I think perhaps, the main thing is not caching the _updates_
            /// in the child state method... right?
            if isCachingEnabled {
                cachedContent = content
            }

            delegate.ifDebug {
                $0.treeDidFetchElementContent(for: self)
            }

            return content
        }
    }

    /// Updates the element state with the new element and new environment,
    /// throwing away cached values if needed.
    ///
    /// This method takes into account the `Comparability` of the element.
    ///
    /// ## Note
    /// This method may only be called once per layout cycle.
    fileprivate func update(
        with newElement: Element,
        in newEnvironment: Environment,
        identifier: ElementIdentifier
    ) {
        precondition(self.identifier == identifier)
        precondition(type(of: newElement) == type(of: element.latest))

        let isEquivalent: Bool

        switch comparability {
        case .notComparable:
            isEquivalent = false

        case .comparableElement:
            isEquivalent = Self.elementsEquivalent(element.latest, newElement)

        case .childOfComparableElement:
            /// We're always, equivalent, because our parent
            /// determines our equatability from its state.
            /// It will also invalidate and throw away _our_ caches if its
            /// equivalency changes.
            isEquivalent = true
        }

        /// If `isEquivalent` is false, we want to blow away all cached data.
        if isEquivalent == false {
            /// Clear our own cached data.
            clearAllCachedData()

            /// 2) If _we_ are a `ComparableElement`, or children which are `.childOfComparableElement`
            /// depend on us to invalidate their measurements; so do so here. It's important to note
            /// that we only clear child caches if those elements themselves are **not** `ComparableElement`.
            if comparability == .comparableElement {
                recursiveForEach {
                    $0.clearAllCachedDataIfNotComparable()
                }
            }
        } else {
            /// If we are equivalent, we still need to throw out any measurements
            /// and layouts that are dependent on the `Environment`. Compare
            /// the stored `Environment.Subset` values to see if any
            /// of the values that we care about are no longer equivalent.

            measurements.removeAll { _, measurement in
                newEnvironment.valuesEqual(to: measurement.dependencies) == false
            }

            layouts.removeAll { _, layout in
                newEnvironment.valuesEqual(to: layout.dependencies) == false
            }
        }

        /// Update our `LatestElement` to the element's new value.
        /// This will allow cached `LayoutResultNodes` to ensure they
        /// have access to the latest `backingViewDescription`.

        element.latest = newElement

        hasUpdated = true

        delegate.ifDebug {
            $0.treeDidUpdateState(self)
        }
    }

    /// Represents a cached measurement, which contains
    /// both the output measurements and the dependencies
    /// from the `Environment`, if any.
    struct CachedMeasurement {
        var size: CGSize
        var dependencies: Environment.Subset?
    }

    /// Invoked by `ElementContent` to generate a measurement via the `measurer`,
    /// or return a cached measurement if one exists.
    func measure(
        in constraint: SizeConstraint,
        with environment: Environment,
        using measurement: (Environment) -> CGSize
    ) -> CGSize {
        /// We already have a cached measurement, reuse that.
        if let existing = measurements[constraint] {
            delegate.ifDebug {
                $0.treeDidReturnCachedMeasurement(existing, constraint: constraint, for: self)
            }

            return existing.size
        }

        /// Perform the measurement and track the environment dependencies.
        let (size, dependencies) = trackDependenciesIfNeeded(
            in: environment,
            during: measurement
        )

        /// Save the measurement for next time.

        let measurement = CachedMeasurement(
            size: size,
            dependencies: dependencies
        )

        measurements[constraint] = measurement

        delegate.ifDebug {
            $0.treeDidPerformMeasurement(measurement, constraint: constraint, for: self)
        }

        return size
    }

    /// Represents a cached `LayoutResultNode` tree of all children,
    /// which contains both child tree, and the dependencies
    /// from the `Environment`, if any.
    struct CachedLayout {
        var nodes: [LayoutResultNode]
        var dependencies: Environment.Subset?
    }

    /// Invoked by `ElementContent` to generate a layout tree via the `layout`,
    /// or return a cached layout tree if one exists.
    func layout(
        in size: CGSize,
        with environment: Environment,
        using layout: (Environment) -> [LayoutResultNode]
    ) -> [LayoutResultNode] {

        /// Layout is only invoked once per cycle. If we're not a `ComparableElement`,
        /// there's no point in caching this value, so just return the `layout` directly.
        ///
        /// We are **not** also applying this to `.childOfComparableElement` as well,
        /// because that parent `ComparableElement` will perform the layout tree caching.
        guard comparability == .comparableElement else {
            let nodes = layout(environment)

            delegate.ifDebug {
                $0.treeDidPerformLayout(nodes, size: size, for: self)
            }

            return nodes
        }

        /// We already have a cached layout, reuse that.
        if let existing = layouts[size] {
            delegate.ifDebug {
                $0.treeDidReturnCachedLayout(existing, size: size, for: self)
            }

            if hasUpdatedChildrenDuringLayout == false {
                hasUpdatedChildrenDuringLayout = true

                /// Because we're returning a cached layout, we're not going to be
                /// enumerating every child element in the tree during layout. To resolve
                /// this, we'll perform an enumeration over the tree.

                elementContent.enumerateAllNodes(
                    in: size,
                    with: existing.nodes,
                    for: element.latest,
                    with: self,
                    environment: environment,
                    forEachLayoutNode: { state, element in

                        /// Guarantees that the latest element is present in the tree.
                        /// in case its `backingViewDescription` has changed,
                        /// for example (while remaining equivalent), eg it needs to apply
                        /// a new callback closure to the view.
                        state.element.latest = element

                        /// Also ensure we update our element content.
                        /// TODO: Do we need to do this?
                        state.cachedContent = element.content

                        /// Because we won't be visiting any child elements
                        /// for a `ComparableElement` during either
                        /// measurement or layout, mark all our child nodes
                        /// as visited so they are not torn down.
                        state.wasVisited = true
                    },
                    forEachMeasurementOnlyNode: { state in
                        state.wasVisited = true
                    }
                )
            }

            return existing.nodes
        }

        /// Perform the layout and track the environment dependencies.

        let (nodes, dependencies) = trackDependenciesIfNeeded(
            in: environment,
            during: layout
        )

        /// Save the layout for next time.

        let layout = CachedLayout(
            nodes: nodes,
            dependencies: dependencies
        )

        layouts[size] = layout

        delegate.ifDebug {
            $0.treeDidPerformCachedLayout(layout, for: self)
        }

        return nodes
    }

    /// Used by measurement and layout to track the dependencies they have on the `Environment`.
    /// The method returns the output from your `toTrack` callback, as well as
    /// an `Environment.Subset` that represents the measurement or layout's dependencies on the `Environment`.
    ///
    /// If there are no dependencies (`toTrack` did not read from the `Environment`), no subset is returned.
    ///
    /// Additionally, if the element is not comparable, no subset is returned or tracked.
    private func trackDependenciesIfNeeded<Output>(
        in environment: Environment,
        during toTrack: (Environment) -> Output
    ) -> (Output, Environment.Subset?) {

        /// We only need to append a read observer if we are a `comparableElement`.
        /// If we're a `.childOfComparableElement`, the read subscription
        /// from the upstream comparable element will still be applied.
        guard comparability == .comparableElement else {
            return (toTrack(environment), nil)
        }

        var environment = environment
        var observedKeys = Set<Environment.StorageKey>()

        environment.subscribeToReads { key in
            observedKeys.insert(key)
        }

        let output = toTrack(environment)

        return (output, environment.subset(with: observedKeys))
    }

    /// Creates a new child `ElementState` for the provided `Element`,
    /// or returns an existing one if it already exists.
    ///
    /// The first time the element is seen during a layout traversal, we will call `update`
    /// on its backing `ElementState` to keep internal state in sync.
    func childState(
        for child: Element,
        in environment: Environment,
        with identifier: ElementIdentifier
    ) -> ElementState {

        if let existing = children[identifier] {

            existing.wasVisited = true

            if existing.elementContent.dynamicallyGeneratesContent {

                /// Our element content is entirely dependent on dynamic layout
                /// tree attributes like the `SizeConstraint` or `Environment`
                /// content, eg we're a `GeometryReader` or `EnvironmentReader`.
                /// Rather than being clever about when we can and can't update the child during
                /// tree enumeration, just update it on every pass.

                existing.update(with: child, in: environment, identifier: identifier)
            } else if existing.hasUpdated == false {

                /// We are not a dynamic element, so we only need to update if we've not
                /// been seen before.

                existing.update(with: child, in: environment, identifier: identifier)
            }

            return existing
        } else {
            let new = ElementState(
                parent: self,
                delegate: delegate,
                identifier: identifier,
                element: child,
                signpostRef: signpostRef,
                name: name
            )

            children[identifier] = new

            delegate.ifDebug {
                $0.treeDidCreateState(new)
            }

            return new
        }
    }

    /// To be called at the beginning of the layout cycle by the owner
    /// of the `ElementStateTree`, to set up the tree for a traversal.
    fileprivate func prepareForLayout() {
        recursiveForEach {
            $0.wasVisited = false
            $0.hasUpdated = false
            $0.hasUpdatedChildrenDuringLayout = false
        }
    }

    /// To be called at the end of the layout cycle by the owner
    /// of the `ElementStateTree`, to tear down any old state,
    /// or throw out caches which should not be maintained across layout cycles.
    fileprivate func finishedLayout() {
        recursiveRemoveOldChildren()
        recursiveClearCaches()
    }

    /// Clears all cached measurements, layouts, etc.
    private func clearAllCachedData() {
        measurements.removeAll()
        layouts.removeAll()
    }

    /// Clears all cached data, but only if the element is **not** a `ComparableElement`.
    private func clearAllCachedDataIfNotComparable() {
        if comparability != .comparableElement {
            clearAllCachedData()
        }
    }

    /// Performs a depth-first enumeration of all elements in the tree,
    /// _including_ the original reciever.
    func recursiveForEach(_ perform: (ElementState) -> Void) {
        perform(self)

        children.forEach { _, child in
            child.recursiveForEach(perform)
        }
    }

    /// Iterating the whole tree, garbage collects all children
    /// which are no longer present in the tree.
    private func recursiveRemoveOldChildren() {

        for (key, state) in children {

            if state.wasVisited { continue }

            children.removeValue(forKey: key)

            delegate.ifDebug {
                $0.treeDidRemoveState(state)
            }
        }

        children.forEach { _, state in
            state.recursiveRemoveOldChildren()
        }
    }

    /// Iterating the whole tree, clears caches which should
    /// not be maintained after the current layout cycle.
    private func recursiveClearCaches() {
        recursiveForEach {
            if $0.comparability.isComparable == false {
                $0.clearAllCachedData()
            }

            /// **TODO:** Should we cache this across layout cycles too? I think no,
            /// because we're already caching layout nodes, so this shouldn't even be called.
            /// But we should verify that!
            $0.cachedContent = nil
        }
    }
}


extension ElementState {

    /// A reference type passed through to `LayoutResultNode` and `NativeViewNode`,
    /// so that even when returning cached layouts, we can get to the latest version of the element
    /// that their originating `ElementState` represents.
    final class LatestElement {

        fileprivate(set) var latest: Element

        init(_ latest: Element) {
            self.latest = latest
        }
    }

    /// TODO: Delete
    /// A "last instance" cache, returning a cached value, or creating a new value
    struct Cache<Key: Hashable, Value> {

        /// The cache behavior. See `CacheKind` for more.
        let kind: CacheKind

        /// If the cached value will vary by the provided key,
        /// or if the key is ignored.
        var variesByKey: Bool {
            didSet {
                if oldValue != variesByKey {
                    removeAll()
                }
            }
        }

        private var byKeyValues: [Key: Value] = [:]
        private var singleValue: Value? = nil

        init(kind: CacheKind, variesByKey: Bool) {
            self.kind = kind
            self.variesByKey = variesByKey
        }

        mutating func removeAll() {
            byKeyValues.removeAll(keepingCapacity: true)
            singleValue = nil
        }

        mutating func removeValue(forKey key: Key) {
            byKeyValues.removeValue(forKey: key)
            singleValue = nil
        }

        func hasValue(for key: Key) -> Bool {
            if variesByKey {
                return byKeyValues[key] != nil
            } else {
                return singleValue != nil
            }
        }

        mutating func get(_ key: Key, provider: () -> Value) -> Value {

            if variesByKey {
                singleValue = nil

                if let value = byKeyValues[key] {
                    return value
                } else {
                    let value = provider()
                    byKeyValues[key] = value
                    return value
                }
            } else {
                byKeyValues.removeAll(keepingCapacity: false)

                if let singleValue {
                    return singleValue
                } else {
                    let value = provider()
                    singleValue = value
                    return value
                }
            }
        }
    }

    enum CacheKind {
        case cacheAll
        case cacheLatest
    }
}


extension CGSize: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
    }
}


/// A token reference type that can be used to group associated signpost logs using `OSSignpostID`.
private final class SignpostToken {}


extension ElementState {

    /// Checks if the two elements are equivalent in the given context.
    ///
    /// - If both values are nil, `true` is returned.
    /// - If both values are different types, `false` is returned.
    static func elementsEquivalent(_ lhs: Element?, _ rhs: Element?) -> Bool {

        if lhs == nil && rhs == nil { return true }

        guard let lhs = lhs as? AnyComparableElement else { return false }
        guard let rhs = rhs as? AnyComparableElement else { return false }

        return lhs.anyIsEquivalent(to: rhs)
    }
}


extension Dictionary {

    /// Removes all values from the dictionary that pass the provided predicate.
    fileprivate mutating func removeAll(where shouldRemove: (Key, Value) -> Bool) {

        for (key, value) in self {
            if shouldRemove(key, value) {
                removeValue(forKey: key)
            }
        }
    }
}

//
// MARK: ElementStateTreeDelegate
//

/// A delegate object that is called during layout to inspect the actions performed
/// during the layout and measurement process.
protocol ElementStateTreeDelegate: AnyObject {

    /// Root `ElementState`

    func tree(_ tree: ElementStateTree, didSetupRootState state: ElementState)
    func tree(_ tree: ElementStateTree, didUpdateRootState state: ElementState)
    func tree(_ tree: ElementStateTree, didTeardownRootState state: ElementState)
    func tree(_ tree: ElementStateTree, didReplaceRootState state: ElementState, with new: ElementState)

    /// Creating / Updating `ElementState`

    func treeDidCreateState(_ state: ElementState)
    func treeDidUpdateState(_ state: ElementState)
    func treeDidRemoveState(_ state: ElementState)

    func treeDidFetchElementContent(for state: ElementState)

    /// Measuring & Laying Out

    func treeDidReturnCachedMeasurement(
        _ measurement: ElementState.CachedMeasurement,
        constraint: SizeConstraint,
        for state: ElementState
    )

    func treeDidPerformMeasurement(
        _ measurement: ElementState.CachedMeasurement,
        constraint: SizeConstraint,
        for state: ElementState
    )

    func treeDidReturnCachedLayout(
        _ layout: ElementState.CachedLayout,
        size: CGSize,
        for state: ElementState
    )

    func treeDidPerformLayout(
        _ layout: [LayoutResultNode],
        size: CGSize,
        for state: ElementState
    )

    func treeDidPerformCachedLayout(
        _ layout: ElementState.CachedLayout,
        for state: ElementState
    )
}


extension Optional where Wrapped == ElementStateTreeDelegate {
    func ifDebug(perform block: (Wrapped) -> Void) {
        #if DEBUG
            if let self = self {
                block(self)
            }
        #endif
    }
}


//
// MARK: CustomDebugStringConvertible
//


extension ElementState: CustomDebugStringConvertible {

    public var debugDescription: String {
        "<ElementState \(address(of: self)): \(identifier.debugDescription)>"
    }

    public var recursiveDebugDescription: String {
        var debugRepresentations = [ElementState.DebugRepresentation]()

        children.values.forEach {
            $0.appendDebugDescriptions(to: &debugRepresentations, at: 0)
        }

        let strings: [String] = debugRepresentations.map { child in
            Array(repeating: "  ", count: child.depth).joined() + child.debugDescription
        }

        let all = ["<ElementState \(address(of: self)): \(identifier.debugDescription)>"] + strings

        return all.joined(separator: "\n")
    }
}


extension ElementState {

    private func appendDebugDescriptions(to: inout [DebugRepresentation], at depth: Int) {

        let info = DebugRepresentation(
            objectIdentifier: ObjectIdentifier(self),
            depth: depth,
            identifier: identifier,
            element: element.latest,
            measurements: measurements
        )

        to.append(info)

        children.values.forEach { child in
            child.appendDebugDescriptions(to: &to, at: depth + 1)
        }
    }

    private struct DebugRepresentation: CustomDebugStringConvertible {
        var objectIdentifier: ObjectIdentifier
        var depth: Int
        var identifier: ElementIdentifier
        var element: Element
        var measurements: [SizeConstraint: CachedMeasurement]

        var debugDescription: String {
            "\(identifier.debugDescription): \(measurements.count) Measurements"
        }
    }
}


