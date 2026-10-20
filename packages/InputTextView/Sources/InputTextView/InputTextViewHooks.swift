import Cocoa
import TGUIKit
import TelegramContext
import TelegramCore

public protocol InputInlineAvatarLayer: SimpleLayer {
}

public struct InputTextViewHooks {
    public let checkSendingAbility: (NSEvent) -> Bool
    public let showDateSelector: (any AccountContextProtocol, Window, Date, @escaping (Date) -> Void) -> Void
    public let showPremiumBoarding: (any AccountContextProtocol, Window) -> Void
    public let showTranslate: (any AccountContextProtocol, Window, String?, String, @escaping (NSAttributedString) -> Void) -> Void
    public let showURLFormatter: (Window, String, String?, [String], @escaping (String, String?) -> Void) -> Void
    public let makeInlineAvatarLayer: (any AccountContextProtocol, NSRect, EnginePeer) -> any InputInlineAvatarLayer

    public init(checkSendingAbility: @escaping (NSEvent) -> Bool,
                showDateSelector: @escaping (any AccountContextProtocol, Window, Date, @escaping (Date) -> Void) -> Void,
                showPremiumBoarding: @escaping (any AccountContextProtocol, Window) -> Void,
                showTranslate: @escaping (any AccountContextProtocol, Window, String?, String, @escaping (NSAttributedString) -> Void) -> Void,
                showURLFormatter: @escaping (Window, String, String?, [String], @escaping (String, String?) -> Void) -> Void,
                makeInlineAvatarLayer: @escaping (any AccountContextProtocol, NSRect, EnginePeer) -> any InputInlineAvatarLayer) {
        self.checkSendingAbility = checkSendingAbility
        self.showDateSelector = showDateSelector
        self.showPremiumBoarding = showPremiumBoarding
        self.showTranslate = showTranslate
        self.showURLFormatter = showURLFormatter
        self.makeInlineAvatarLayer = makeInlineAvatarLayer
    }

    private static var installed: InputTextViewHooks?

    public static var shared: InputTextViewHooks {
        guard let hooks = installed else {
            fatalError("InputTextViewHooks.install must be called before the input view is used")
        }
        return hooks
    }

    public static func install(_ hooks: InputTextViewHooks) {
        installed = hooks
    }
}
