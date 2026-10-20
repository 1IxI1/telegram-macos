import Cocoa
import TGUIKit
import TelegramMedia
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import InAppSettings
import ChatModeTypes

public protocol PremiumStickerView: AnyObject {
    func updatePremiumSticker(file: TelegramMediaFile, size: NSSize, context: any AccountContextProtocol, tint: NSColor?, animated: Bool)
    func updatePremiumStickerLayout(size: NSSize, transition: ContainedViewLayoutTransition)
}

public struct PremiumHooks {
    public let openChat: (any AccountContextProtocol, PeerId, ChatInitialAction?) -> Void
    public let makeStickerView: (NSRect) -> NSView
    public let applyMessageEntities: ([MessageTextEntity], String, any AccountContextProtocol, CGFloat, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void, NSColor?, Bool, Bool) -> NSAttributedString
    public let showStickerPackPreview: (any AccountContextProtocol, String) -> Void
    public let openBusinessFeature: (any AccountContextProtocol, PremiumValue) -> Void
    public let preloadVideo: (any AccountContextProtocol, TelegramMediaFile) -> Signal<Never, NoError>
    public let openLink: (any AccountContextProtocol, String, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Void

    public init(openChat: @escaping (any AccountContextProtocol, PeerId, ChatInitialAction?) -> Void,
                makeStickerView: @escaping (NSRect) -> NSView,
                applyMessageEntities: @escaping ([MessageTextEntity], String, any AccountContextProtocol, CGFloat, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void, NSColor?, Bool, Bool) -> NSAttributedString,
                showStickerPackPreview: @escaping (any AccountContextProtocol, String) -> Void,
                openBusinessFeature: @escaping (any AccountContextProtocol, PremiumValue) -> Void,
                preloadVideo: @escaping (any AccountContextProtocol, TelegramMediaFile) -> Signal<Never, NoError>,
                openLink: @escaping (any AccountContextProtocol, String, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Void) {
        self.openChat = openChat
        self.makeStickerView = makeStickerView
        self.applyMessageEntities = applyMessageEntities
        self.showStickerPackPreview = showStickerPackPreview
        self.openBusinessFeature = openBusinessFeature
        self.preloadVideo = preloadVideo
        self.openLink = openLink
    }

    private static var value: PremiumHooks?

    public static var shared: PremiumHooks {
        guard let value = value else {
            preconditionFailure("PremiumHooks not installed")
        }
        return value
    }

    public static func install(_ hooks: PremiumHooks) {
        self.value = hooks
    }
}

public func installPremiumHooks(_ hooks: PremiumHooks) {
    PremiumHooks.install(hooks)
}
