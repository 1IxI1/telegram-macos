import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import PremiumUI
import TelegramMediaPlayer

func installPremiumUIHooks() {
    installPremiumHooks(.init(openChat: { context, peerId, action in
        guard let context = context as? AccountContext else {
            return
        }
        let navigation = context.bindings.rootNavigation()
        let chat = navigation.first { $0 is ChatController } as? ChatController
        if chat?.chatInteraction.peerId == peerId {
            navigation.back()
            if let action = action {
                chat?.chatInteraction.invokeInitialAction(action: action)
            }
        } else {
            navigateToChat(navigation: navigation, context: context, chatLocation: .peer(peerId), initialAction: action)
        }
    }, makeStickerView: { frame in
        return MediaAnimatedStickerView(frame: frame)
    }, applyMessageEntities: { entities, text, context, fontSize, openInfo, textColor, isDark, bubbled in
        guard let context = context as? AccountContext else {
            return NSAttributedString()
        }
        if let textColor = textColor {
            return ChatMessageItem.applyMessageEntities(with: [TextEntitiesMessageAttribute(entities: entities)], for: text, message: nil, context: context, fontSize: fontSize, openInfo: openInfo, textColor: textColor, isDark: isDark, bubbled: bubbled)
        }
        return ChatMessageItem.applyMessageEntities(with: [TextEntitiesMessageAttribute(entities: entities)], for: text, message: nil, context: context, fontSize: fontSize, openInfo: openInfo, isDark: isDark, bubbled: bubbled)
    }, showStickerPackPreview: { context, shortName in
        guard let context = context as? AccountContext else {
            return
        }
        showModal(with: StickerPackPreviewModalController(context, peerId: nil, references: [.emoji(.name(shortName))]), for: context.window)
    }, openBusinessFeature: { context, value in
        guard let context = context as? AccountContext else {
            return
        }
        let navigation = context.bindings.rootNavigation()
        switch value {
        case .business_location:
            navigation.push(BusinessLocationController(context: context))
        case .business_hours:
            navigation.push(BusinessHoursController(context: context))
        case .quick_replies:
            navigation.push(BusinessQuickReplyController(context: context))
        case .greeting_message:
            navigation.push(BusinessMessageController(context: context, type: .greetings))
        case .away_message:
            navigation.push(BusinessMessageController(context: context, type: .away))
        case .business_bots:
            navigation.push(BusinessChatbotController(context: context))
        case .business_intro:
            navigation.push(BusinessIntroController(context: context))
        case .business_links:
            navigation.push(BusinessLinksController(context: context))
        default:
            break
        }
    }, preloadVideo: { context, video in
        guard let context = context as? AccountContext else {
            return .complete()
        }
        return preloadVideoResource(postbox: context.account.postbox, userLocation: .other, userContentType: .init(file: video), resourceReference: .standalone(resource: video.resource), duration: 3.0)
    }, openLink: { context, url, openInfo in
        guard let context = context as? AccountContext else {
            return
        }
        execute(inapp: inApp(for: url.nsstring, context: context, openInfo: openInfo))
    }))
}

extension MediaAnimatedStickerView: @retroactive PremiumStickerView {
    public func updatePremiumSticker(file: TelegramMediaFile, size: NSSize, context: any AccountContextProtocol, tint: NSColor?, animated: Bool) {
        guard let context = context as? AccountContext else {
            return
        }
        if let tint = tint {
            let parameters = ChatAnimatedStickerMediaLayoutParameters(playPolicy: .loop, alwaysAccept: true, media: file, colors: [.init(keyPath: "", color: tint)], noThumb: true)
            self.update(with: file, size: size, context: context, table: nil, parameters: parameters, animated: animated)
        } else {
            self.update(with: file, size: size, context: context, table: nil, animated: animated)
        }
    }
    public func updatePremiumStickerLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        self.updateLayout(size: size, transition: transition)
    }
}
