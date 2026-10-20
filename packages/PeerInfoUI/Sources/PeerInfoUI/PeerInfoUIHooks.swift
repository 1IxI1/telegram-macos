import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import ChatModeTypes
import AudioPlayerCore

public protocol PeerInfoPremiumConfiguration {
    var minChannelAutotranslationLevel: Int32 { get }
}

@available(macOS 10.15, *)
public struct PeerInfoWalletHooks {
    public let hasWallet: (any AccountContextProtocol) -> Bool
    public let sendMoney: (any AccountContextProtocol, Peer) -> Void

    public init(hasWallet: @escaping (any AccountContextProtocol) -> Bool,
                sendMoney: @escaping (any AccountContextProtocol, Peer) -> Void) {
        self.hasWallet = hasWallet
        self.sendMoney = sendMoney
    }
}

public struct PeerInfoUIHooks {
    public let freezeAlert: (any AccountContextProtocol) -> Void
    public let formatPhoneNumber: (any AccountContextProtocol, String) -> String
    public let resolveUsername: (String, any AccountContextProtocol) -> Signal<Peer?, NoError>
    public let premiumConfiguration: (any AccountContextProtocol) -> any PeerInfoPremiumConfiguration
    public let showDisableSharingModal: (any AccountContextProtocol, PeerId, @escaping (Bool) -> Void) -> Void
    public let showInlineAudioPlayer: (APController, any AccountContextProtocol, TableView?, TableView?) -> Void
    public let showProfileMusicPlayerList: (any AccountContextProtocol, EnginePeer, TelegramMediaFile, ProfileSavedMusicContext.State, ProfileSavedMusicContext) -> Void
    public let executeNftLink: (String, String, any AccountContextProtocol) -> Void
    public let navigateToChat: (NavigationViewController?, any AccountContextProtocol, ChatLocation, ChatMode, ChatFocusTarget?, Atomic<ChatLocationContextHolder?>?) -> Void
    public let wallet: Any?

    public init(freezeAlert: @escaping (any AccountContextProtocol) -> Void,
                formatPhoneNumber: @escaping (any AccountContextProtocol, String) -> String,
                resolveUsername: @escaping (String, any AccountContextProtocol) -> Signal<Peer?, NoError>,
                premiumConfiguration: @escaping (any AccountContextProtocol) -> any PeerInfoPremiumConfiguration,
                showDisableSharingModal: @escaping (any AccountContextProtocol, PeerId, @escaping (Bool) -> Void) -> Void,
                showInlineAudioPlayer: @escaping (APController, any AccountContextProtocol, TableView?, TableView?) -> Void,
                showProfileMusicPlayerList: @escaping (any AccountContextProtocol, EnginePeer, TelegramMediaFile, ProfileSavedMusicContext.State, ProfileSavedMusicContext) -> Void,
                executeNftLink: @escaping (String, String, any AccountContextProtocol) -> Void,
                navigateToChat: @escaping (NavigationViewController?, any AccountContextProtocol, ChatLocation, ChatMode, ChatFocusTarget?, Atomic<ChatLocationContextHolder?>?) -> Void,
                wallet: Any?) {
        self.freezeAlert = freezeAlert
        self.formatPhoneNumber = formatPhoneNumber
        self.resolveUsername = resolveUsername
        self.premiumConfiguration = premiumConfiguration
        self.showDisableSharingModal = showDisableSharingModal
        self.showInlineAudioPlayer = showInlineAudioPlayer
        self.showProfileMusicPlayerList = showProfileMusicPlayerList
        self.executeNftLink = executeNftLink
        self.navigateToChat = navigateToChat
        self.wallet = wallet
    }

    @available(macOS 10.15, *)
    public var walletHooks: PeerInfoWalletHooks {
        return wallet as! PeerInfoWalletHooks
    }

    private static var _shared: PeerInfoUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: PeerInfoUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("PeerInfoUIHooks.install must be called before peer info screens are used")
        return .placeholder
    }

    public static func install(_ hooks: PeerInfoUIHooks) {
        assert(Thread.isMainThread, "PeerInfoUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = PeerInfoUIHooks(freezeAlert: { _ in
    }, formatPhoneNumber: { _, number in
        number
    }, resolveUsername: { _, _ in
        .single(nil)
    }, premiumConfiguration: { _ in
        PeerInfoPlaceholderPremiumConfiguration()
    }, showDisableSharingModal: { _, _, _ in
    }, showInlineAudioPlayer: { _, _, _, _ in
    }, showProfileMusicPlayerList: { _, _, _, _, _ in
    }, executeNftLink: { _, _, _ in
    }, navigateToChat: { _, _, _, _, _, _ in
    }, wallet: nil)
}

struct PeerInfoPlaceholderPremiumConfiguration: PeerInfoPremiumConfiguration {
    var minChannelAutotranslationLevel: Int32 { return 3 }
}
