import XCTest
@testable import BlueprintUI


class EnvironmentTests: XCTestCase {

    func test_default() {
        let testValue = TestValue.defaultValue
        let element = AdaptingElement()

        let view = TestView()
        let size = element.content.measure(in: .unconstrained, environment: .empty)
        let layoutResultNode = element.layout(frame: .zero)

        let attributes = leafAttributes(in: element.layout(frame: .zero))
        let viewDescription = leafViewDescription(
            in: NativeViewNode(
                content: UIView.describe { _ in },
                environment: .empty,
                layoutAttributes: LayoutAttributes(frame: .zero),
                children: layoutResultNode.resolve()
            ))

        viewDescription.apply(to: view)

        XCTAssertEqual(size, testValue.size)
        XCTAssertEqual(attributes, testValue.layoutAttributes)
        XCTAssertEqual(view.testValue, testValue)
    }

    func test_adapted() {
        let testValue = TestValue.right
        let element = AdaptedEnvironment(
            key: TestKey.self,
            value: testValue,
            wrapping: AdaptingElement()
        )

        let view = TestView()
        let size = element.content.measure(in: .unconstrained, environment: .empty)
        let layoutResultNode = element.layout(frame: .zero)

        let attributes = leafAttributes(in: element.layout(frame: .zero))
        let viewDescription = leafViewDescription(
            in: NativeViewNode(
                content: UIView.describe { _ in },
                environment: .empty,
                layoutAttributes: LayoutAttributes(frame: .zero),
                children: layoutResultNode.resolve()
            ))

        viewDescription.apply(to: view)

        XCTAssertEqual(size, testValue.size)
        XCTAssertEqual(attributes, testValue.layoutAttributes)
        XCTAssertEqual(view.testValue, testValue)
    }

    func test_nestedAdapter() {
        let testValue = TestValue.right
        let element = AdaptedEnvironment(
            key: TestKey.self,
            value: .wrong,
            wrapping: AdaptedEnvironment(
                key: TestKey.self,
                value: testValue,
                wrapping: AdaptingElement()
            )
        )

        let view = TestView()
        let size = element.content.measure(in: .unconstrained, environment: .empty)
        let layoutResultNode = element.layout(frame: .zero)

        let attributes = leafAttributes(in: element.layout(frame: .zero))
        let viewDescription = leafViewDescription(
            in: NativeViewNode(
                content: UIView.describe { _ in },
                environment: .empty,
                layoutAttributes: LayoutAttributes(frame: .zero),
                children: layoutResultNode.resolve()
            ))

        viewDescription.apply(to: view)

        XCTAssertEqual(size, testValue.size)
        XCTAssertEqual(attributes, testValue.layoutAttributes)
        XCTAssertEqual(view.testValue, testValue)
    }

    func test_viewBackedAdapted() {
        let rightElement = AdaptedEnvironment(
            key: TestKey.self,
            value: .right,
            wrapping: TestViewBackedElement()
        )

        let rightLayoutResultNode = rightElement.layout(frame: .zero)
        let rightViewDescription = leafViewDescription(
            in: NativeViewNode(
                content: UIView.describe { _ in },
                environment: .empty,
                layoutAttributes: LayoutAttributes(frame: .zero),
                children: rightLayoutResultNode.resolve()
            ))

        let view = TestView()

        rightViewDescription.apply(to: view)

        XCTAssertEqual(view.testValue, .right)

        // Ensure updating the environment works

        let wrongElement = AdaptedEnvironment(
            key: TestKey.self,
            value: .wrong,
            wrapping: TestViewBackedElement()
        )

        let wrongLayoutResultNode = wrongElement.layout(frame: .zero)
        let wrongViewDescription = leafViewDescription(
            in: NativeViewNode(
                content: UIView.describe { _ in },
                environment: .empty,
                layoutAttributes: LayoutAttributes(frame: .zero),
                children: wrongLayoutResultNode.resolve()
            ))

        wrongViewDescription.apply(to: view)

        XCTAssertEqual(view.testValue, .wrong)
    }

    func test_viewBackedNestedAdapter() {
        let testValue = TestValue.right
        let element = AdaptedEnvironment(
            key: TestKey.self,
            value: .wrong,
            wrapping: AdaptedEnvironment(
                key: TestKey.self,
                value: testValue,
                wrapping: TestViewBackedElement()
            )
        )

        let view = TestView()
        let layoutResultNode = element.layout(frame: .zero)
        let viewDescription = leafViewDescription(
            in: NativeViewNode(
                content: UIView.describe { _ in },
                environment: .empty,
                layoutAttributes: LayoutAttributes(frame: .zero),
                children: layoutResultNode.resolve()
            ))

        viewDescription.apply(to: view)

        XCTAssertEqual(view.testValue, testValue)
    }

    func test_merged() {
        var lhs = Environment.empty
        lhs[TestKey.self] = .wrong
        lhs[LHSTestKey.self] = 2


        var rhs = Environment.empty
        rhs[TestKey.self] = .right
        rhs[RHSTestKey.self] = 3

        let output = lhs.merged(prioritizing: rhs)

        XCTAssertEqual(output[TestKey.self], .right)
        XCTAssertEqual(output[LHSTestKey.self], 2)
        XCTAssertEqual(output[RHSTestKey.self], 3)

        enum LHSTestKey: EnvironmentKey { static let defaultValue: Int? = nil }
        enum RHSTestKey: EnvironmentKey { static let defaultValue: Int? = nil }
    }

    func test_subscribeToReads() throws {

        var environment = Environment.empty

        var reads1 = [Environment.StorageKey]()
        var reads2 = [Environment.StorageKey]()

        environment.subscribeToReads { key in
            reads1.append(key)
        }

        environment.subscribeToReads { key in
            reads2.append(key)
        }

        environment[TestKey.self] = .right

        _ = environment[TestKey.self]

        XCTAssertEqual(reads1.count, 1)
        XCTAssertEqual(reads2.count, 1)

        XCTAssertEqual(Environment.StorageKey(TestKey.self), try XCTUnwrap(reads1.first))
        XCTAssertEqual(Environment.StorageKey(TestKey.self), try XCTUnwrap(reads2.first))
    }

    func test_equality() {

        // Not equal
        do {
            var lhs = Environment.empty
            lhs[TestKey.self] = .wrong
            lhs[LHSTestKey.self] = 2


            var rhs = Environment.empty
            rhs[TestKey.self] = .right
            rhs[RHSTestKey.self] = 3

            XCTAssertNotEqual(lhs, rhs)

        }

        // Not equal
        do {
            var lhs = Environment.empty
            lhs[TestKey.self] = .wrong
            lhs[LHSTestKey.self] = 2


            var rhs = Environment.empty
            rhs[TestKey.self] = .wrong
            rhs[RHSTestKey.self] = 2

            XCTAssertNotEqual(lhs, rhs)
        }

        // Equal
        do {
            var lhs = Environment.empty
            lhs[TestKey.self] = .wrong
            lhs[LHSTestKey.self] = 2


            var rhs = Environment.empty
            rhs[TestKey.self] = .wrong
            rhs[LHSTestKey.self] = 2

            XCTAssertEqual(lhs, rhs)
        }

        enum LHSTestKey: EnvironmentKey { static let defaultValue: Int? = nil }
        enum RHSTestKey: EnvironmentKey { static let defaultValue: Int? = nil }
    }

    func test_subset() {

        var environment = Environment.empty

        environment[Key1.self] = 1
        environment[Key2.self] = 2
        environment[Key3.self] = 3

        let subset = environment.subset(with: Set([Key1.storageKey, Key2.storageKey, Key4.storageKey]))
        XCTAssertEqual(subset?.values.count, 2)
        let keys = Set(subset!.values.keys)
        XCTAssertTrue(keys.contains(Key1.storageKey))
        XCTAssertTrue(keys.contains(Key2.storageKey))
        enum Key1: EnvironmentKey { static let defaultValue: Int? = nil }
        enum Key2: EnvironmentKey { static let defaultValue: Int? = nil }
        enum Key3: EnvironmentKey { static let defaultValue: Int? = nil }
        enum Key4: EnvironmentKey { static let defaultValue: Int? = nil }
    }

    func test_valuesEqual() {

        var environment = Environment.empty

        environment[Key1.self] = 1
        environment[Key2.self] = 2
        environment[Key3.self] = 3

        let subset1 = environment.subset(with: Set([Key1.storageKey, Key2.storageKey]))
        let subset2 = environment.subset(with: Set([Key1.storageKey, Key2.storageKey, Key3.storageKey]))

        var matchEnvironment = Environment.empty
        matchEnvironment[Key1.self] = 1
        matchEnvironment[Key2.self] = 2

        XCTAssertTrue(matchEnvironment.valuesEqual(to: subset1))
        XCTAssertFalse(matchEnvironment.valuesEqual(to: subset2))


        enum Key1: EnvironmentKey { static let defaultValue: Int? = nil }
        enum Key2: EnvironmentKey { static let defaultValue: Int? = nil }
        enum Key3: EnvironmentKey { static let defaultValue: Int? = nil }
    }

    func leafAttributes(in node: LayoutResultNode) -> LayoutAttributes {
        if let childNode = node.children.first {
            return leafAttributes(in: childNode)
        }
        return node.layoutAttributes
    }

    func leafViewDescription(in node: NativeViewNode) -> ViewDescription {
        if let child = node.children.first?.node {
            return leafViewDescription(in: child)
        }
        return node.viewDescription
    }

    struct AdaptingElement: ProxyElement {
        var elementRepresentation: Element {
            EnvironmentReader { environment -> Element in
                TestElement(value: environment.testValue)
            }
        }
    }
}


class Environment_UIView_Tests: XCTestCase {

    func test_inheritedBlueprintEnvironment() {

        var environment = Environment.empty
        environment[TestingKey1.self] = 1

        let first = View(subview: View(subview: View(subview: nil)))
        let second = first.subviews[0]
        let third = second.subviews[0]

        first.nativeViewNodeBlueprintEnvironment = environment

        XCTAssertEqual(first.inheritedBlueprintEnvironment?[TestingKey1.self], 1)
        XCTAssertEqual(second.inheritedBlueprintEnvironment?[TestingKey1.self], 1)
        XCTAssertEqual(third.inheritedBlueprintEnvironment?[TestingKey1.self], 1)

        first.nativeViewNodeBlueprintEnvironment = nil

        XCTAssertEqual(first.inheritedBlueprintEnvironment?[TestingKey1.self], nil)
        XCTAssertEqual(second.inheritedBlueprintEnvironment?[TestingKey1.self], nil)
        XCTAssertEqual(third.inheritedBlueprintEnvironment?[TestingKey1.self], nil)
    }

    enum TestingKey1: EnvironmentKey { static let defaultValue: Int? = nil }

    private final class View: UIView {

        init(subview: UIView?) {
            super.init(frame: .zero)

            if let subview = subview {
                addSubview(subview)
            }
        }

        required init?(coder: NSCoder) { fatalError() }
    }
}

/// A view-backed element with one child, whose measurement, layout, and view description varies
/// based on the passed in test value.
private struct TestElement: Element {
    var value: TestValue

    var content: ElementContent {
        ElementContent(
            layout: TestLayout(value: value),
            configure: { layout in
                layout.add(element: Spacer(size: CGSize(width: 8, height: 8)))
            }
        )
    }

    struct TestLayout: Layout {
        var value: TestValue

        func measure(in constraint: SizeConstraint, items: [(traits: (), content: Measurable)]) -> CGSize {
            value.size
        }

        func layout(size: CGSize, items: [(traits: (), content: Measurable)]) -> [LayoutAttributes] {
            [value.layoutAttributes]
        }
    }

    func backingViewDescription(with context: ViewDescriptionContext) -> ViewDescription? {
        TestView.describe { config in
            config[\.testValue] = self.value
        }
    }
}

private class TestViewBackedElement: Element {
    var content: ElementContent {
        ElementContent(intrinsicSize: .zero)
    }

    func backingViewDescription(with context: ViewDescriptionContext) -> ViewDescription? {
        TestView.describe { config in
            config[\.testValue] = context.environment[TestKey.self]
        }
    }
}

private class TestView: UIView {
    var testValue = TestValue.defaultValue
}

private enum TestValue {
    case defaultValue
    case wrong
    case right

    var size: CGSize {
        switch self {
        case .defaultValue:
            return CGSize(width: 2, height: 3)
        case .right:
            return CGSize(width: 4, height: 5)
        case .wrong:
            return CGSize(width: 6, height: 7)
        }
    }

    var layoutAttributes: LayoutAttributes {
        LayoutAttributes(size: size)
    }
}

private enum TestKey: EnvironmentKey {
    static let defaultValue = TestValue.defaultValue
}

extension Environment {
    fileprivate var testValue: TestValue {
        get { self[TestKey.self] }
        set { self[TestKey.self] = newValue }
    }
}


extension EnvironmentKey {
    fileprivate static var storageKey: Environment.StorageKey {
        .init(Self.self)
    }
}
