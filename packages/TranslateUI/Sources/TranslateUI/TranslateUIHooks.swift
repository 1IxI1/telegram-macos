import Cocoa
import TGUIKit
import TelegramCore
import TelegramContext

public struct TranslateUIHooks {
    public let showAboutCocoonModal: (any AccountContextProtocol) -> Void
    public let shareLink: (any AccountContextProtocol, String) -> Void
    public let followResolvedName: (String, String, any AccountContextProtocol) -> Void
    public let showStyleEmojiPicker: (any AccountContextProtocol, Control, @escaping (TelegramMediaFile) -> Void) -> Void

    public init(showAboutCocoonModal: @escaping (any AccountContextProtocol) -> Void,
                shareLink: @escaping (any AccountContextProtocol, String) -> Void,
                followResolvedName: @escaping (String, String, any AccountContextProtocol) -> Void,
                showStyleEmojiPicker: @escaping (any AccountContextProtocol, Control, @escaping (TelegramMediaFile) -> Void) -> Void) {
        self.showAboutCocoonModal = showAboutCocoonModal
        self.shareLink = shareLink
        self.followResolvedName = followResolvedName
        self.showStyleEmojiPicker = showStyleEmojiPicker
    }

    private static var _shared: TranslateUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: TranslateUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("TranslateUIHooks.install must be called before translate screens are used")
        return .placeholder
    }

    public static func install(_ hooks: TranslateUIHooks) {
        assert(Thread.isMainThread, "TranslateUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = TranslateUIHooks(showAboutCocoonModal: { _ in
    }, shareLink: { _, _ in
    }, followResolvedName: { _, _, _ in
    }, showStyleEmojiPicker: { _, _, _ in
    })
}
