import CoreGraphics

/// Content storage that applies a change to the environment.
struct EnvironmentAdaptingStorage: ContentStorage {

    typealias IdentifiedNode = ElementContent.IdentifiedNode

    let childCount = 1

    /// During measurement or layout, the environment adapter will be applied
    /// to the environment before passing it
    ///
    var adapter: (inout Environment) -> Void

    var child: Element
    var content: ElementContent
    var identifier: ElementIdentifier

    init(adapter: @escaping (inout Environment) -> Void, child: Element) {
        self.adapter = adapter
        self.child = child
        content = child.content
        identifier = ElementIdentifier(elementType: type(of: child), key: nil, count: 1)
    }

    private func adapted(environment: Environment) -> Environment {
        var environment = environment
        adapter(&environment)
        return environment
    }
}

extension EnvironmentAdaptingStorage: CaffeinatedContentStorage {

    func sizeThatFits(
        proposal: SizeConstraint,
        environment: Environment,
        node: LayoutTreeNode
    ) -> CGSize {
        let environment = adapted(environment: environment)
        let subnode = node.subnode(key: identifier)
        return content.sizeThatFits(proposal: proposal, environment: environment, node: subnode)
    }

    func performCaffeinatedLayout(
        frame: CGRect,
        environment: Environment,
        node: LayoutTreeNode
    ) -> [IdentifiedNode] {
        let environment = adapted(environment: environment)
        let childAttributes = LayoutAttributes(size: frame.size)
        let subnode = node.subnode(key: identifier)

        let node = LayoutResultNode(
            element: child,
            layoutAttributes: childAttributes,
            environment: environment,
            children: content.performCaffeinatedLayout(
                frame: frame,
                environment: environment,
                node: subnode
            )
        )

        return [(identifier, node)]
    }
}
