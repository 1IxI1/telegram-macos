import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import TelegramMediaUtils
import InlineMediaGrid
import ChatModeTypes

public enum EntertainmentStickerPackPreviewSource: Hashable {
    case stickers(StickerPackReference)
    case emoji(StickerPackReference)
}

public enum EntertainmentPreviewKind {
    case gif
    case animatedSticker
    case sticker
}

public protocol EntertainmentStickerContentView: View {
    func updateSticker(file: TelegramMediaFile, size: NSSize, context: any AccountContextProtocol, table: TableView?, animated: Bool)
    func stickerShake()
    func stickerUpdateMouse()
    func stickerWillRemove()
}

public final class EntertainmentMediaArguments {
    public let sendResult: (ChatContextResultCollection?, ChatContextResult, NSView) -> Void
    public let menuItems: (TelegramMediaFile, NSView) -> Signal<[ContextMenuItem], NoError>
    public let openMessage: (Message) -> Void
    public let messageMenuItems: (Message, NSView) -> Signal<[ContextMenuItem], NoError>

    public init(sendResult: @escaping (ChatContextResultCollection?, ChatContextResult, NSView) -> Void = { _, _, _ in }, menuItems: @escaping (TelegramMediaFile, NSView) -> Signal<[ContextMenuItem], NoError> = { _, _ in return .single([]) }, openMessage: @escaping (Message) -> Void = { _ in }, messageMenuItems: @escaping (Message, NSView) -> Signal<[ContextMenuItem], NoError> = { _, _ in return .single([]) }) {
        self.sendResult = sendResult
        self.menuItems = menuItems
        self.openMessage = openMessage
        self.messageMenuItems = messageMenuItems
    }
}

public struct EntertainmentUIHooks {
    public let makePreviewSender: (TelegramMediaFile, any ChatInteractionProtocol) -> ModalViewController
    public let shareLink: (any AccountContextProtocol, String) -> Void
    public let makeChatInteraction: (any AccountContextProtocol, PeerId) -> any ChatInteractionProtocol
    public let currentChatInteraction: (any AccountContextProtocol) -> (any ChatInteractionProtocol)?
    public let makeTopicIconFile: (String, Int32, Bool) -> TelegramMediaFile
    public let inputSource: (any AccountContextProtocol) -> InputSources
    public let makeStickerPackPreview: (any AccountContextProtocol, PeerId?, [EntertainmentStickerPackPreviewSource]) -> ModalViewController
    public let previewViewType: (EntertainmentPreviewKind) -> ModalPreviewControllerView.Type
    public let makeStickerContentView: (Bool, NSRect) -> any EntertainmentStickerContentView
    public let makeContextMediaRowItem: (NSSize, InputMediaContextRow, Int64, any AccountContextProtocol, EntertainmentMediaArguments, ChatContextResultCollection?, AnyHashable) -> TableRowItem
    public let launchSendFlight: (any ChatInteractionProtocol, NSView, NSRect, CALayer?) -> Void

    public init(makePreviewSender: @escaping (TelegramMediaFile, any ChatInteractionProtocol) -> ModalViewController,
                shareLink: @escaping (any AccountContextProtocol, String) -> Void,
                makeChatInteraction: @escaping (any AccountContextProtocol, PeerId) -> any ChatInteractionProtocol,
                currentChatInteraction: @escaping (any AccountContextProtocol) -> (any ChatInteractionProtocol)?,
                makeTopicIconFile: @escaping (String, Int32, Bool) -> TelegramMediaFile,
                inputSource: @escaping (any AccountContextProtocol) -> InputSources,
                makeStickerPackPreview: @escaping (any AccountContextProtocol, PeerId?, [EntertainmentStickerPackPreviewSource]) -> ModalViewController,
                previewViewType: @escaping (EntertainmentPreviewKind) -> ModalPreviewControllerView.Type,
                makeStickerContentView: @escaping (Bool, NSRect) -> any EntertainmentStickerContentView,
                makeContextMediaRowItem: @escaping (NSSize, InputMediaContextRow, Int64, any AccountContextProtocol, EntertainmentMediaArguments, ChatContextResultCollection?, AnyHashable) -> TableRowItem,
                launchSendFlight: @escaping (any ChatInteractionProtocol, NSView, NSRect, CALayer?) -> Void = { _, _, _, _ in }) {
        self.makePreviewSender = makePreviewSender
        self.shareLink = shareLink
        self.makeChatInteraction = makeChatInteraction
        self.currentChatInteraction = currentChatInteraction
        self.makeTopicIconFile = makeTopicIconFile
        self.inputSource = inputSource
        self.makeStickerPackPreview = makeStickerPackPreview
        self.previewViewType = previewViewType
        self.makeStickerContentView = makeStickerContentView
        self.makeContextMediaRowItem = makeContextMediaRowItem
        self.launchSendFlight = launchSendFlight
    }

    private static var _shared: EntertainmentUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: EntertainmentUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("EntertainmentUIHooks.install must be called before the entertainment panel is used")
        fatalError("EntertainmentUIHooks.install must be called before the entertainment panel is used")
    }

    public static func install(_ hooks: EntertainmentUIHooks) {
        assert(Thread.isMainThread, "EntertainmentUIHooks.install must be called on the main thread")
        _shared = hooks
    }
}
