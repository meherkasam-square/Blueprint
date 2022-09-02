import BlueprintUI
import BlueprintUICommonControls
import UIKit


struct HelloWorldElement: ProxyElement {

    var elementRepresentation: Element {
        var label = Label(text: "Hello, world")
        label.font = .boldSystemFont(ofSize: 24.0)
        label.color = .darkGray

        return Centered(label)
    }
}


final class ViewController: UIViewController {

    private let blueprintView = BlueprintView(element: HelloWorldElement())

    override func loadView() {
        view = blueprintView
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

}
