import Cocoa
import TGUIKit
import SwiftSignalKit
import WalletUI
import StarsUI

func installWalletUIHooks() {
    var hooks = WalletUIHooks()
    hooks.appPasslock = {
        return (NSApp.delegate as? AppDelegate)?.passlock ?? .single(false)
    }
    hooks.openTonEarnings = { context in
        showModal(with: Star_ListScreen(context: context, currency: .ton, source: .account), for: context.window)
    }
    WalletUIHooks.install(hooks)
}
