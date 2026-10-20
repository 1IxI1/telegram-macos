import Cocoa
import TelegramCore
import Localization
import Postbox
import SwiftSignalKit
import TGUIKit
import InAppSettings
import ColorPalette
import ThemeSettings
import TelegramTheme
import TelegramContext
import AlertsUI

public func joinChannel(context: any AccountContextProtocol, peerId: PeerId) {

    _ = showModalProgress(signal: context.engine.peers.joinChannel(peerId: peerId, hash: nil) |> deliverOnMainQueue, for: context.window).start(next: { outcome in
        switch outcome {
        case .joined:
            _ = showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 1.5).start()
        case let .webView(webView):
            ChatNavigationHooks.shared.openJoinChatBotWebView(context, webView.botPeer.id, webView.url, webView.queryId, peerId)
        }
    }, error: { error in
        let text: String
        switch error {
        case .generic:
            text = strings().unknownError
        case .tooMuchJoined:
            ChatNavigationHooks.shared.showInactiveChannelsOnJoin(context)
            return
        case .tooMuchUsers:
            text = strings().groupUsersTooMuchError
        case .inviteRequestSent:
            showModalText(for: context.window, text: strings().chatSendJoinRequestInfo, title: strings().chatSendJoinRequestTitle)
            return
        }
        alert(for: context.window, info: text)
    })
}
