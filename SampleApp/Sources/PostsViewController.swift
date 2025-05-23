import BlueprintUI
import BlueprintUICommonControls
import UIKit


struct Post: Equatable {
    var authorName: String = "Me"
    var date: Date = Date()
    var body: String = ""
    var isFave: Bool = false
}


final class PostsViewController: UIViewController {

    struct State {
        var isLoading = false
        var posts: [Post] = [
            Post(
                authorName: "Tim",
                date: Calendar.current.date(byAdding: .hour, value: -1, to: Date())!,
                body: "Lorem Ipsum"
            ),
            Post(
                authorName: "Jane",
                date: Calendar.current.date(byAdding: .day, value: -2, to: Date())!,
                body: "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
            ),
            Post(
                authorName: "John",
                date: Calendar.current.date(byAdding: .day, value: -2, to: Date())!,
                body: "Lorem ipsum dolor sit amet, consectetur adipiscing elit!"
            ),
        ]
        var entry: Post = Post()

        mutating func publishEntry() {
            posts.append(entry)
            entry = Post()
        }

        mutating func didFave(_ post: Post) {
            guard let index = posts.firstIndex(of: post) else { return }
            var new = post
            new.isFave.toggle()
            posts[index] = new
        }
    }

    private let blueprintView = BlueprintView()
    private var state = State() {
        didSet {
            update()
        }
    }

    override func loadView() {
        view = blueprintView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        update()
    }

    private func update() {
        blueprintView.element = element
    }

    private func startLoading() {
        state.isLoading = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.finishLoading()
        }
    }

    private func finishLoading() {
        state.isLoading = false
    }

    var element: Element {
        let theme = FeedTheme(authorColor: .green)

        let pullToRefreshBehavior: ScrollView.PullToRefreshBehavior
        if state.isLoading {
            pullToRefreshBehavior = .refreshing
        } else {
            pullToRefreshBehavior = .enabled(action: { [weak self] in
                self?.startLoading()
            })
        }

        return MainView(
            state: state,
            onChange: { [weak self] field, text in
                guard let self = self else { return }
                switch field {
                case .name:
                    self.state.entry.authorName = text
                case .body:
                    self.state.entry.body = text
                }
            },
            onSubmit: { [weak self] in
                self?.state.publishEntry()
            },
            didFave: { [weak self] post in
                self?.state.didFave(post)
            },
            didRT: { [weak self] post in
                guard let self else { return }
                let author = state.entry.authorName
                state.entry.authorName = author
                self.state.entry.body = "RT: @\(post.authorName) \(post.body)"
                self.state.publishEntry()
            },
            pullToRefreshBehavior: pullToRefreshBehavior

        )
        .adaptedEnvironment(keyPath: \.feedTheme, value: theme)
    }
}

extension Environment {
    private enum FeedThemeKey: EnvironmentKey {
        static let defaultValue = FeedTheme(authorColor: .black)
    }

    var feedTheme: FeedTheme {
        get { self[FeedThemeKey.self] }
        set { self[FeedThemeKey.self] = newValue }
    }
}

struct FeedTheme {
    var authorColor: UIColor
}

fileprivate struct MainView: ProxyElement {

    var state: PostsViewController.State
    var onChange: (EntryForm.Field, String) -> Void
    var onSubmit: () -> Void

    var didFave: (Post) -> Void
    var didRT: (Post) -> Void

    var pullToRefreshBehavior: ScrollView.PullToRefreshBehavior


    var elementRepresentation: Element {
        EnvironmentReader { environment -> Element in
            Column { col in
                col.horizontalAlignment = .fill

                col.add(child: List(posts: state.posts, didFave: didFave, didRT: didRT))
                col.add(
                    child: EntryForm(
                        entry: state.entry,
                        onChange: onChange,
                        onSubmit: onSubmit
                    )
                )
            }
            .scrollable {
                $0.contentSize = .fittingHeight
                $0.alwaysBounceVertical = true
                $0.keyboardDismissMode = .onDrag
                $0.pullToRefreshBehavior = self.pullToRefreshBehavior
            }
            .inset(by: environment.safeAreaInsets)
            .box(background: UIColor(white: 0.95, alpha: 1.0))
        }
    }
}

fileprivate struct List: ProxyElement {

    var posts: [Post]

    var didFave: (Post) -> Void
    var didRT: (Post) -> Void

    var elementRepresentation: Element {
        Column { col in
            col.horizontalAlignment = .fill
            col.minimumVerticalSpacing = 8.0

            for post in posts {
                col.add(child: FeedItem(post: post, didFave: didFave, didRT: didRT))
            }
        }
    }
}

fileprivate struct EntryForm: ProxyElement {

    enum Field: Hashable {
        case name, body
    }

    var entry: Post
    var onChange: (Field, String) -> Void
    var onSubmit: () -> Void

    @FocusState var focusedField: Field?

    var elementRepresentation: Element {
        Column { col in
            col.horizontalAlignment = .fill

            col.add(child: Label(text: "New post:"))

            col.addFixed(
                child: TextField(text: entry.authorName) { field in
                    field.placeholder = "Name"
                    field.onReturn = {
                        focusedField = .body
                    }
                    field.onChange = { text in
                        onChange(.name, text)
                    }
                }
                .focused(when: $focusedField, equals: .name)
            )

            col.addFixed(
                child: TextField(text: entry.body) { field in
                    field.placeholder = "Comment"
                    field.onChange = { text in
                        onChange(.body, text)
                    }
                    field.onReturn = {
                        focusedField = nil
                        onSubmit()
                    }
                }
                .focused(when: $focusedField, equals: .body)
            )
        }
        .inset(uniform: 16.0)
        .box(background: .lightGray)
        .onAppear {
            focusedField = .name
        }
    }
}


fileprivate struct FeedItem: ProxyElement {

    var post: Post

    var didFave: (Post) -> Void
    var didRT: (Post) -> Void

    var buttons: Element {
        Row {
            Button(onTap: { didFave(post) }, wrapping: Label(text: post.isFave ? "★" : "☆") {
                $0.font = .boldSystemFont(ofSize: 36.0)
                $0.color = UIColor.systemYellow
            })
            .transition(onLayout: .specific(.spring(
                mass: 1,
                stiffness: 200,
                damping: 7,
                initialVelocity: .zero
            )))
            .rotated(by: .init(value: post.isFave ? 72 : 0.0, unit: .degrees))
            .accessibilityElement(
                label: post.isFave ? "Unfave @\(post.authorName)'s post" : "Fave @\(post.authorName)'s Post",
                value: nil,
                traits: [.button]
            )

            Button(onTap: { didRT(post) }, wrapping: Label(text: "↺") {
                $0.font = .boldSystemFont(ofSize: 36.0)
                $0.color = UIColor.systemBlue
            })
            .accessibilityElement(label: "RT @\(post.authorName)'s Post", value: nil, traits: [.button])

        }
    }

    var elementRepresentation: Element {
        Column { col in
            let content = Row { row in
                row.verticalAlignment = .top
                row.minimumHorizontalSpacing = 16.0
                row.horizontalUnderflow = .growUniformly

                let avatar = Box(
                    backgroundColor: .lightGray,
                    cornerStyle: .rounded(radius: 32.0)
                ).constrainedTo(width: .absolute(64.0), height: .absolute(64.0))

                row.add(
                    growPriority: 0.0,
                    shrinkPriority: 0.0,
                    child: avatar
                )

                row.add(
                    growPriority: 1.0,
                    shrinkPriority: 1.0,
                    child: FeedItemBody(post: post)
                )
            }
            col.add(child: content)

            col.add(child: buttons)
        }
        .accessibilityContainer(
            containerType: .semanticGroup,
            label: post.authorName,
            value: post.isFave ? "Faved" : nil
        )
        .inset(uniform: 16.0)
        .box(background: .white)
    }

}

fileprivate struct FeedItemBody: ProxyElement {

    var post: Post

    let dateFormatter: Formatter = {
        RelativeDateTimeFormatter()
    }()

    var elementRepresentation: Element {
        let column = Column { col in

            col.horizontalAlignment = .leading
            col.minimumVerticalSpacing = 8.0

            let header = Row { row in
                row.minimumHorizontalSpacing = 8.0
                row.verticalAlignment = .center

                let name = EnvironmentReader { environment -> Element in
                    var name = Label(text: self.post.authorName)
                    name.font = UIFont.boldSystemFont(ofSize: 14.0)
                    name.color = environment.feedTheme.authorColor
                    return name
                }
                row.add(child: name)

                var timeAgo = Label(text: dateFormatter.string(for: post.date)!)
                timeAgo.font = UIFont.systemFont(ofSize: 14.0)
                timeAgo.color = .lightGray
                row.add(child: timeAgo)
            }

            col.add(child: header)

            var body = Label(text: post.body)
            body.font = UIFont.systemFont(ofSize: 13.0)

            col.add(child: body)
        }
        .accessibilityElement(label: post.body, value: dateFormatter.string(for: post.date), traits: [.staticText])

        return column
    }

}
