import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import AudioPlayerCore
import ChatHistoryModel
import RichTextEditorUI
import RichTextEditorCore
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import TelegramMediaResources
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils

public protocol ChatInputControllerView: NSView {
    var inputView: ChatInputView { get }
}

public enum ChatInputInAppLink {
    case external(link: String, Bool)
    case other
}

public enum ChatInputStickerPackPreviewSource : Hashable {
    case stickers(StickerPackReference)
    case emoji(StickerPackReference)
}

@available(macOS 10.15, *)
public struct ChatInputWalletHooks {
    public let walletContext: (any AccountContextProtocol) -> (any ChatWalletContext)?
    public let makeWalletSendController: (any AccountContextProtocol, any ChatWalletContext, Peer, ChatWalletSendHandlers) -> ModalViewController

    public init(walletContext: @escaping (any AccountContextProtocol) -> (any ChatWalletContext)?,
                makeWalletSendController: @escaping (any AccountContextProtocol, any ChatWalletContext, Peer, ChatWalletSendHandlers) -> ModalViewController) {
        self.walletContext = walletContext
        self.makeWalletSendController = makeWalletSendController
    }
}

public struct ChatInputUIHooks {
    public let makeEntertainmentsPopover: (ChatInteraction) -> ViewController
    public let makeSuggestPostPanelModel: (ChatInterfaceState.ChannelSuggestPost, any AccountContextProtocol) -> ChatAccessoryModel
    public let makeUrlPreviewModel: (any AccountContextProtocol, TelegramMediaWebpage, String) -> ChatAccessoryModel
    public let makeEditMessageModel: (ChatEditState, any AccountContextProtocol) -> ChatAccessoryModel
    public let makeForwardPanelModel: ([Message], Bool, any AccountContextProtocol) -> ChatAccessoryModel
    public let makeForwardMessagesModal: (any AccountContextProtocol, [Message]) -> ModalViewController
    public let makeTranslateModal: (any AccountContextProtocol, String?, String, String, @escaping (NSAttributedString) -> Void, @escaping (NSAttributedString) -> Void) -> ModalViewController
    public let makeRichTranslateModal: (any AccountContextProtocol, String?, String, String, [MessageTextEntity], [Block], @escaping ([Block]) -> Void) -> ModalViewController
    public let wallet: Any?
    public let getAudioPlayer: ((any AccountContextProtocol)?) -> APController?
    public let makeStickerPackPreview: (any AccountContextProtocol, PeerId?, [ChatInputStickerPackPreviewSource]) -> ModalViewController
    public let resolveInAppLink: (Any?) -> ChatInputInAppLink?
    public let highlightRichTextSyntax: (String, String, @escaping () -> TelegramPresentationTheme, @escaping ([RichTextSyntaxToken]) -> Void) -> Void
    public let makeEmojiPicker: (any AccountContextProtocol, @escaping (StickerPackItem, StarGift.UniqueGift?, StickerPackCollectionInfo?, Int32?, NSRect?) -> Void, @escaping (String, CGRect?) -> Void) -> ViewController

    public init(makeEntertainmentsPopover: @escaping (ChatInteraction) -> ViewController,
                makeSuggestPostPanelModel: @escaping (ChatInterfaceState.ChannelSuggestPost, any AccountContextProtocol) -> ChatAccessoryModel,
                makeUrlPreviewModel: @escaping (any AccountContextProtocol, TelegramMediaWebpage, String) -> ChatAccessoryModel,
                makeEditMessageModel: @escaping (ChatEditState, any AccountContextProtocol) -> ChatAccessoryModel,
                makeForwardPanelModel: @escaping ([Message], Bool, any AccountContextProtocol) -> ChatAccessoryModel,
                makeForwardMessagesModal: @escaping (any AccountContextProtocol, [Message]) -> ModalViewController,
                makeTranslateModal: @escaping (any AccountContextProtocol, String?, String, String, @escaping (NSAttributedString) -> Void, @escaping (NSAttributedString) -> Void) -> ModalViewController,
                makeRichTranslateModal: @escaping (any AccountContextProtocol, String?, String, String, [MessageTextEntity], [Block], @escaping ([Block]) -> Void) -> ModalViewController,
                wallet: Any?,
                getAudioPlayer: @escaping ((any AccountContextProtocol)?) -> APController?,
                makeStickerPackPreview: @escaping (any AccountContextProtocol, PeerId?, [ChatInputStickerPackPreviewSource]) -> ModalViewController,
                resolveInAppLink: @escaping (Any?) -> ChatInputInAppLink?,
                highlightRichTextSyntax: @escaping (String, String, @escaping () -> TelegramPresentationTheme, @escaping ([RichTextSyntaxToken]) -> Void) -> Void,
                makeEmojiPicker: @escaping (any AccountContextProtocol, @escaping (StickerPackItem, StarGift.UniqueGift?, StickerPackCollectionInfo?, Int32?, NSRect?) -> Void, @escaping (String, CGRect?) -> Void) -> ViewController) {
        self.makeEntertainmentsPopover = makeEntertainmentsPopover
        self.makeSuggestPostPanelModel = makeSuggestPostPanelModel
        self.makeUrlPreviewModel = makeUrlPreviewModel
        self.makeEditMessageModel = makeEditMessageModel
        self.makeForwardPanelModel = makeForwardPanelModel
        self.makeForwardMessagesModal = makeForwardMessagesModal
        self.makeTranslateModal = makeTranslateModal
        self.makeRichTranslateModal = makeRichTranslateModal
        self.wallet = wallet
        self.getAudioPlayer = getAudioPlayer
        self.makeStickerPackPreview = makeStickerPackPreview
        self.resolveInAppLink = resolveInAppLink
        self.highlightRichTextSyntax = highlightRichTextSyntax
        self.makeEmojiPicker = makeEmojiPicker
    }

    @available(macOS 10.15, *)
    public var walletHooks: ChatInputWalletHooks {
        return wallet as! ChatInputWalletHooks
    }

    private static var _shared: ChatInputUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: ChatInputUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("ChatInputUIHooks.install must be called before the chat input is used")
        return .placeholder
    }

    public static func install(_ hooks: ChatInputUIHooks) {
        assert(Thread.isMainThread, "ChatInputUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = ChatInputUIHooks(makeEntertainmentsPopover: { _ in
        ViewController()
    }, makeSuggestPostPanelModel: { _, context in
        ChatAccessoryModel(context: context)
    }, makeUrlPreviewModel: { context, _, _ in
        ChatAccessoryModel(context: context)
    }, makeEditMessageModel: { _, context in
        ChatAccessoryModel(context: context)
    }, makeForwardPanelModel: { _, _, context in
        ChatAccessoryModel(context: context)
    }, makeForwardMessagesModal: { _, _ in
        ModalViewController()
    }, makeTranslateModal: { _, _, _, _, _, _ in
        ModalViewController()
    }, makeRichTranslateModal: { _, _, _, _, _, _, _ in
        ModalViewController()
    }, wallet: nil, getAudioPlayer: { _ in
        nil
    }, makeStickerPackPreview: { _, _, _ in
        ModalViewController()
    }, resolveInAppLink: { _ in
        nil
    }, highlightRichTextSyntax: { _, _, _, completion in
        completion([])
    }, makeEmojiPicker: { _, _, _ in
        ViewController()
    })
}
