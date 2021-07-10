//
//  ElementState.swift
//  BlueprintUI
//
//  Created by Kyle Van Essen on 6/24/21.
//

import Foundation


final class RootElementState {
    
    private(set) var root : ElementState?
    
    private let signpostRef : SignpostToken = .init()
    let name : String
        
    init(name : String) {
        self.name = name
    }
    
    func update(with element : Element?, in environment : Environment) {
        
        func makeRoot(with element : Element) {
            self.root = ElementState(
                identifier: .init(element: element, key: nil, count: 1),
                element: element,
                depth: 0,
                signpostRef: self.signpostRef,
                name: self.name
            )
        }
        
        if self.root == nil, let element = element {
            makeRoot(with: element)
        } else if let root = self.root, element == nil {
            root.teardown()
            self.root = nil
        } else if let root = self.root, let element = element {
            if type(of: root.element) == type(of: element) {
                root.update(with: element, in: environment, identifier: root.identifier)
            } else {
                root.teardown()
                makeRoot(with: element)
            }
        }
    }
}


final class ElementState {
    
    let identifier : ElementIdentifier
    let depth : Int
    let signpostRef : AnyObject
    let name : String
    
    private(set) var element : Element
    
    let isElementComparable : Bool
    
    private(set) var wasVisited : Bool = false
    private(set) var hasUpdatedInCurrentCycle : Bool = false
                    
    init(
        identifier : ElementIdentifier,
        element : Element,
        depth : Int,
        signpostRef : AnyObject,
        name : String
    ) {
        self.identifier = identifier
        self.element = element
        self.isElementComparable = self.element is AnyComparableElement
        
        self.depth = depth
        self.signpostRef = signpostRef
        self.name = name
        
        self.wasVisited = true
        self.hasUpdatedInCurrentCycle = true
    }
    
    func update(
        with newElement : Element,
        in newEnvironment : Environment,
        identifier : ElementIdentifier
    ) {
        precondition(self.identifier == identifier)
        
        if Self.elementsEquivalent(self.element, newElement) == false {
            self.clearAllCachedData()
        } else {
            self.measurements.removeAll { _, measurement in
                newEnvironment.valuesEqual(to: measurement.dependencies) == false
            }
            
            self.layouts.removeAll { _, layout in
                newEnvironment.valuesEqual(to: layout.dependencies) == false
            }
        }
        
        self.element = newElement
    }
    
    func setup() {
        
    }
    
    func teardown() {
        
    }
    
    private var measurements: [SizeConstraint:CachedMeasurement] = [:]
    
    private struct CachedMeasurement {
        var size : CGSize
        var dependencies : Environment.Subset?
    }

    func measure(
        in constraint : SizeConstraint,
        with context : LayoutContext,
        using measurer : (LayoutContext) -> CGSize
    ) -> CGSize
    {
        if let existing = self.measurements[constraint] {
            return existing.size
        }
        
        let (size, dependencies) = self.trackEnvironmentReads(with: context, in: measurer)
        
        self.measurements[constraint] = .init(
            size: size,
            dependencies: dependencies
        )
                
        return size
    }
    
    typealias LayoutResult = [(identifier: ElementIdentifier, node: LayoutResultNode)]
    
    private var layouts : [CGSize:CachedLayoutResult] = [:]
    
    private struct CachedLayoutResult {
        var result : LayoutResult
        var dependencies : Environment.Subset?
    }
    
    func layout(
        in size : CGSize,
        with context : LayoutContext,
        using layout : (LayoutContext) -> LayoutResult
    ) -> LayoutResult {
        
        if let existing = self.layouts[size] {
            return existing.result
        }
                
        let (result, dependencies) = self.trackEnvironmentReads(with: context, in: layout)
        
        self.layouts[size] = .init(
            result: result,
            dependencies: dependencies
        )
                
        return result
    }
    
    private func trackEnvironmentReads<Output>(
        with context : LayoutContext,
        in toTrack : (LayoutContext) -> Output
    ) -> (Output, Environment.Subset?)
    {
        var context = context
        var observedKeys = Set<Environment.StorageKey>()
        
        context.environment.onDidRead = { key in
            observedKeys.insert(key)
        }
                
        let output = toTrack(context)
        
        return (output, context.environment.subset(with: observedKeys))
    }
    
    private var children : [ElementIdentifier:ElementState] = [:]
    
    func subState(for child : Element, in environment : Environment, with identifier : ElementIdentifier) -> ElementState {
        if let existing = self.children[identifier] {
            existing.wasVisited = true
            
            if self.hasUpdatedInCurrentCycle == false {
                existing.update(with: child, in: environment, identifier: identifier)
                self.hasUpdatedInCurrentCycle = true
            }
            
            return existing
        } else {
            let new = ElementState(
                identifier: identifier,
                element: child,
                depth: self.depth + 1,
                signpostRef: self.signpostRef,
                name: self.name
            )
            
            self.children[identifier] = new
            
            return new
        }
    }
    
    func viewSizeChanged(from : CGSize, to : CGSize) {
        
        if from == to { return }
        
        if let element = self.element as? AnyComparableElement {
            if element.willSizeChangeAffectLayout(from: from, to: to) {
                self.clearAllCachedData()
            }
        } else {
            self.clearAllCachedData()
        }
        
        self.children.forEach { _, value in
            value.viewSizeChanged(from: from, to: to)
        }
    }
    
    func prepareForLayout() {
        
        self.wasVisited = false
        self.hasUpdatedInCurrentCycle = false
        
        self.children.forEach { _, state in
            state.prepareForLayout()
        }
    }
    
    func finishedLayout() {
        self.removeOldChildren()
        self.clearNonPersistentCaches()
    }
    
    private func removeOldChildren() {
        
        for (key, state) in self.children {
            
            if state.wasVisited { continue }
            
            state.teardown()
            
            self.children.removeValue(forKey: key)
        }
        
        self.children.forEach { _, state in
            state.removeOldChildren()
        }
    }
    
    private func clearAllCachedData() {
        self.measurements.removeAll()
        self.layouts.removeAll()
    }
    
    private func clearNonPersistentCaches() {
        
        if self.isElementComparable == false {
            self.clearAllCachedData()
        }
        
        self.children.forEach { _, state in
            state.clearNonPersistentCaches()
        }
    }
}


extension CGSize : Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.width)
        hasher.combine(self.height)
    }
}


/// A token reference type that can be used to group associated signpost logs using `OSSignpostID`.
private final class SignpostToken {}


fileprivate extension ElementState {
    
    static func elementsEquivalent(_ lhs : Element, _ rhs : Element) -> Bool {
        
        guard let lhs = lhs as? AnyComparableElement else { return false }
        guard let rhs = rhs as? AnyComparableElement else { return false }
        
        return lhs.anyIsEquivalentTo(other: rhs)
    }

}


fileprivate extension Dictionary {
    
    mutating func removeAll(where shouldRemove : (Key, Value) -> Bool) {
        
        for (key, value) in self {
            if shouldRemove(key, value) {
                self.removeValue(forKey: key)
            }
        }
    }
}


//
// MARK: CustomDebugStringConvertible
//


extension ElementState : CustomDebugStringConvertible {
    
    public var debugDescription: String {
        
        var debugRepresentations = [ElementState.DebugRepresentation]()
        
        self.children.values.forEach {
            $0.appendDebugDescriptions(to: &debugRepresentations, at: 0)
        }
        
        let strings : [String] = debugRepresentations.map { child in
            Array(repeating: "  ", count: child.depth).joined() + child.debugDescription
        }
        
        return strings.joined(separator: "\n")
    }
}


extension ElementState {
    
    private func appendDebugDescriptions(to : inout [DebugRepresentation], at depth: Int) {
        
        let info = DebugRepresentation(
            objectIdentifier: ObjectIdentifier(self),
            depth: depth,
            identifier: self.identifier,
            element:self.element,
            measurements: self.measurements,
            layouts: self.layouts
        )
        
        to.append(info)
        
        self.children.values.forEach { child in
            child.appendDebugDescriptions(to: &to, at: depth + 1)
        }
    }
    
    private struct DebugRepresentation : CustomDebugStringConvertible{
        var objectIdentifier : ObjectIdentifier
        var depth : Int
        var identifier : ElementIdentifier
        var element : Element
        var measurements : [SizeConstraint:CachedMeasurement]
        var layouts : [CGSize:CachedLayoutResult]
        
        var debugDescription : String {
            "\(type(of:self.element)) #\(self.identifier.count): \(self.measurements.count) Measurements, \(self.layouts.count) Layouts"
        }
    }
}

