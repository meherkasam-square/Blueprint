import BlueprintUI
import BlueprintUICommonControls
import UIKit

final class AccessibilityViewController: UIViewController {

    private let blueprintView = BlueprintView()

    private var focusTrigger = AccessibilityFocusTrigger()

    override func loadView() {
        view = blueprintView
        blueprintView.element = element
    }

    var element: Element {

        Column {
            Row {
                Label(text: "First element")
                    .accessibilityFocus(trigger: focusTrigger)
                Label(text: "Second element")
            }

            Button(
                onTap: {
                    self.focusTrigger.focus()
                },
                wrapping: Label(text: "post button")
            )
            .centered()
        }
        .inset(uniform: 20)
        .centered()



    }

}
