import CoreGraphics

/// The implementation of an `ElementContent`.
protocol ContentStorage: LegacyContentStorage, CaffeinatedContentStorage {
    var childCount: Int { get }
}

protocol LegacyContentStorage {
    func measure(
        in constraint: SizeConstraint,
        environment: Environment,
        cache: CacheTree
    ) -> CGSize

    func performLegacyLayout(
        attributes: LayoutAttributes,
        environment: Environment,
        cache: CacheTree
    ) -> [ElementContent.IdentifiedNode]
}

protocol CaffeinatedContentStorage {
    func sizeThatFits(
        proposal: SizeConstraint,
        context: MeasureContext
    ) -> CGSize

    func performCaffeinatedLayout(
        frame: CGRect,
        context: LayoutContext
    ) -> [ElementContent.IdentifiedNode]
}

// TODO: temporary conformance

extension CaffeinatedContentStorage {
    public func sizeThatFits(
        proposal: SizeConstraint,
        context: MeasureContext
    ) -> CGSize {
        fatalError("not implemented")
    }

    public func performCaffeinatedLayout(
        frame: CGRect,
        context: LayoutContext
    ) -> [ElementContent.IdentifiedNode] {
        fatalError("not implemented")
    }
}
