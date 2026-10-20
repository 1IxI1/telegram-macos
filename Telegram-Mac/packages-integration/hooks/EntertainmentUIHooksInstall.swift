import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramMediaUtils
import InlineMediaGrid
import ChatModeTypes
import ChatUI
import EntertainmentUI

extension ChatMediaContentView: @retroactive EntertainmentStickerContentView {
    public func updateSticker(file: TelegramMediaFile, size: NSSize, context: any AccountContextProtocol, table: TableView?, animated: Bool) {
        self.update(with: file, size: size, context: context, parent: nil, table: table, parameters: nil, animated: animated, positionFlags: nil, approximateSynchronousValue: false)
    }
    public func stickerShake() {
        self.shake()
    }
    public func stickerUpdateMouse() {
        self.updateMouse()
    }
    public func stickerWillRemove() {
        self.willRemove()
    }
}

func installEntertainmentUIHooks() {
    EntertainmentUIHooks.install(EntertainmentUIHooks(makePreviewSender: { file, chatInteraction in
        return PreviewSenderController(appFile: file, chatInteraction: chatInteraction as! ChatInteraction)
    }, shareLink: { context, link in
        let context = context as! AccountContext
        showModal(with: ShareModalController(ShareLinkObject(context, link: link)), for: context.window)
    }, makeChatInteraction: { context, peerId in
        return ChatInteraction(chatLocation: .peer(peerId), context: context)
    }, currentChatInteraction: { context in
        return (context.bindings.rootNavigation().controller as? ChatInterfaceController)?.chatInteraction
    }, makeTopicIconFile: { title, iconColor, isGeneral in
        return ChatInterfaceHooks.shared.makeTopicIconFile(title, iconColor, isGeneral)
    }, inputSource: { context in
        return ChatInterfaceHooks.shared.inputSource(context)
    }, makeStickerPackPreview: { context, peerId, sources in
        return ChatInputUIHooks.shared.makeStickerPackPreview(context, peerId, sources.map { source in
            switch source {
            case let .stickers(reference):
                return .stickers(reference)
            case let .emoji(reference):
                return .emoji(reference)
            }
        })
    }, previewViewType: { kind in
        switch kind {
        case .gif:
            return GifPreviewModalView.self
        case .animatedSticker:
            return AnimatedStickerPreviewModalView.self
        case .sticker:
            return StickerPreviewModalView.self
        }
    }, makeStickerContentView: { animated, frame in
        return animated ? MediaAnimatedStickerView(frame: frame) : ChatStickerContentView(frame: frame)
    }, makeContextMediaRowItem: { initialSize, row, index, context, arguments, collection, stableId in
        return ContextMediaRowItem(initialSize, row, index, context, ContextMediaArguments(sendResult: arguments.sendResult, menuItems: arguments.menuItems, openMessage: arguments.openMessage, messageMenuItems: arguments.messageMenuItems), collection: collection, stableId: stableId)
    }, launchSendFlight: { chatInteraction, view, rect, sourceLayer in
        guard let chatInteraction = chatInteraction as? ChatInteraction, let source = ChatMediaSendFlightSource(view: view, rect: rect, sourceLayer: sourceLayer) else {
            return
        }
        chatInteraction.mediaSendFlight?.launch(source)
    }))
}
