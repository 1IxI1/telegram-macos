import Cocoa
import TGUIKit
import TelegramContext

public final class InlineTextView: TextView {
    private let inlineRenderer: InlineTextRenderer = GeneralRowsHooks.shared.makeInlineTextRenderer()
    private let animatableContentObserver = AnimatableContentObserver()
    private var isLite: Bool = false

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.userInteractionEnabled = false
        self.isSelectable = false
    }

    public convenience override init() {
        self.init(frame: .zero)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func set(text: TextViewLayout?, context: (any AccountContextProtocol)?, insetEmoji: CGFloat = 0, decreaseAvatar: CGFloat = 0, emojiOffset: NSPoint = .init()) {
        self.update(text)
        if let context, let text {
            self.isLite = context.isLite(.emoji)
            self.inlineRenderer.update(textView: self, layout: text, context: context, insetEmoji: insetEmoji, emojiOffset: emojiOffset, decreaseAvatar: decreaseAvatar)
        } else {
            self.inlineRenderer.clear()
        }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.updateListeners()
        self.updateAnimatableContent()
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        self.updateListeners()
        self.updateAnimatableContent()
    }

    @objc private func updateAnimatableContent() {
        self.inlineRenderer.updateAnimatableContent(window: self.window, isLite: self.isLite)
    }

    private func updateListeners() {
        self.animatableContentObserver.update(for: self, target: self, selector: #selector(updateAnimatableContent), options: [.contentBounds, .documentFrame, .ownFrame])
    }
}
