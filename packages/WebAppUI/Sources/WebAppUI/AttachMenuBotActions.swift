import Cocoa
import Foundation
import WebKit
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import FoundationUtils
import ObjcUtils
import KeyboardKey
import TelegramIconsTheme
import TelegramMedia
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import LocalAnimations
import FilePanels
import TelegramLinks
import PremiumStatusUI
import SystemPermissions
import Svg
import LocalAuthentication

public func installAttachMenuBot(context: (any AccountContextProtocol), peer: Peer, completion: @escaping(Bool)->Void) {
    let signal = context.engine.messages.addBotToAttachMenu(botId: peer.id, allowWrite: true) |> deliverOnMainQueue
    
    _ = signal.start(next: { value in
        if value {
            completion(value)
        }
    })
}

public func openWebBot(_ bot: AttachMenuBot, context: (any AccountContextProtocol)) {
    let open:()->Void = {
        BrowserStateContext.get(context).open(tab: .simple(bot: bot.peer, url: nil, buttonText: "", source: .settings))
    }
    
    if bot.flags.contains(.showInSettingsDisclaimer) || bot.flags.contains(.notActivated) { //
        var options: [ModalAlertData.Option] = []
        options.append(.init(string: strings().webBotAccountDisclaimerThird, isSelected: false, mandatory: true))
        
       
        var description: ModalAlertData.Description? = nil
        let installBot = !bot.flags.contains(.notActivated) && bot.peer._asPeer().botInfo?.flags.contains(.canBeAddedToAttachMenu) == true && !bot.flags.contains(.showInAttachMenu)
        
        if installBot {
            description = .init(string: strings().webBotAccountDesclaimerDesc(bot.shortName), onlyWhenEnabled: false)
        }
        
        let data = ModalAlertData(title: strings().webBotAccountDisclaimerTitle, info: strings().webBotAccountDisclaimerText, description: description, ok: strings().webBotAccountDisclaimerOK, options: options)
        showModalAlert(for: context.window, data: data, completion: { result in
            
            _ = context.engine.messages.acceptAttachMenuBotDisclaimer(botId: bot.peer.id).start()
            installAttachMenuBot(context: context, peer: bot.peer._asPeer(), completion: { value in
                if value, installBot {
                    showModalText(for: context.window, text: strings().webAppAttachSuccess(bot.peer._asPeer().displayTitle))
                }
                open()
            })
        })
    } else {
        open()
    }
}

public func openJoinChatBotWebView(context: (any AccountContextProtocol), botId: PeerId, url: String?, queryId: Int64, joinedPeerId: PeerId?) {
    let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: botId))
    |> deliverOnMainQueue).start(next: { botPeer in
        guard let botPeer else {
            alert(for: context.window, info: strings().unknownError)
            return
        }
        let tabUniqueId: BrowserTabData.Unique = .webapp(queryId)
        // `url` is optional (matches iOS `JoinChatWebView.url`): open the web-app tab now when it's known;
        // when deferred (nil) the bot supplies the resolved URL via a `.webView` join decision below, which
        // reopens with it.
        if let url = url {
            let result = RequestWebViewResult(flags: [], queryId: queryId, url: url, keepAliveSignal: nil)
            let tab: BrowserTabData.Data = .straight(bot: botPeer, peerId: joinedPeerId ?? botId, title: botPeer._asPeer().displayTitle, result: result)
            BrowserStateContext.get(context).open(tab: tab, uniqueId: tabUniqueId)
        }

        _ = (context.account.stateManager.joinChatWebViewDecisions
        |> mapToSignal { decisions -> Signal<JoinChatWebViewDecision, NoError> in
            for decision in decisions where decision.queryId == queryId {
                return .single(decision)
            }
            return .complete()
        }
        |> take(1)
        |> deliverOnMainQueue).start(next: { decision in
            BrowserStateContext.get(context).closeTab(uniqueId: tabUniqueId)
            switch decision.result {
            case .approved:
                _ = showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 1.5).start()
            case .declined:
                alert(for: context.window, info: strings().unknownError)
            case .queued:
                showModalText(for: context.window, text: strings().chatSendJoinRequestInfo, title: strings().chatSendJoinRequestTitle)
            case let .webView(newUrl):
                openJoinChatBotWebView(context: context, botId: botId, url: newUrl, queryId: queryId, joinedPeerId: joinedPeerId)
            }
        })
    })
}
