import Cocoa
import TGUIKit
import Postbox
import PeerInfoUI

func installSimilarPeersUIHooks() {
    SimilarPeersHooks.install(SimilarPeersHooks(
        openChat: { context, peerId in
        guard let context = context as? AccountContext else {
            return
        }
        context.bindings.rootNavigation().push(ChatAdditionController(context: context, chatLocation: .peer(peerId))) }
    ))
}
