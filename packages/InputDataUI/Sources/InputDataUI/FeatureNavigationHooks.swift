import Foundation
import Cocoa
import CoreLocation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramTheme

public enum PremiumBoardingSource: Equatable {
    case settings
    case noAds
    case gracePeriod
    case storyViewers
    case storiesStealthMode
    case storiesSaveToGallery
    case premiumStickers
    case premiumEmoji
    case storiesQuality
    case savedTags
    case aiCompose
    case noforwards
    case channelBoost(PeerId)
}

public enum PremiumLimitKind: Equatable {
    case pin
    case pinInArchive
    case savedGifs
    case folders
    case chatInFolders
    case pinInFolders(PeerGroupId)
    case faveStickers
    case publicLink
    case channels
    case uploadFile(Int?)
    case caption(Int)
    case about(Int)
    case accounts(Int)
    case sharedFolders
    case sharedInvites
}

public enum InactiveChannelsReason {
    case join
    case create
    case upgrade
}

public enum DateSelectorRequest {
    case schedule(PeerId)
    case date(title: String, doneTitle: String)
}

public enum BoostInfoSource {
    case story
    case reactions
}

public enum PaymentCheckoutResult {
    case paid
    case cancelled
    case failed
}

public enum UserLocationRequestResult {
    case success(CLLocation)
    case restricted
    case notDetermined
    case denied
    case wifiRequired
    case disabled
}

public struct SponsoredReportOption: Equatable {
    public let text: String
    public let id: Data
    public init(text: String, id: Data) {
        self.text = text
        self.id = id
    }
}

public struct SponsoredReportPage: Equatable {
    public let title: String
    public let options: [SponsoredReportOption]
    public init(title: String, options: [SponsoredReportOption]) {
        self.title = title
        self.options = options
    }
}

public enum FeatureModalKind {
    case premiumBoarding
    case previewSender
}

public struct FeatureNavigationHooks {
    public var showPremiumBoarding: (any AccountContextProtocol, Window, PremiumBoardingSource?, Bool, TelegramPresentationTheme?) -> Void = { _, _, _, _, _ in }
    public var showPremiumLimit: (any AccountContextProtocol, PremiumLimitKind) -> Void = { _, _ in }
    public var makePremiumLockModal: () -> ModalViewController? = { nil }
    public var showStarsPurchase: (any AccountContextProtocol, Window, CurrencyAmount.Currency, String?, Int64?) -> Void = { _, _, _, _, _ in }
    public var selectDate: (any AccountContextProtocol, Window, Date?, Int32?, DateSelectorRequest, @escaping (Date, Int32?) -> Void) -> Void = { _, _, _, _, _, _ in }
    public var selectTimeRange: (any AccountContextProtocol, Window, TimePickerOption, TimePickerOption, String, String, String, String, @escaping (TimePickerOption, TimePickerOption) -> Void) -> Void = { _, _, _, _, _, _, _, _, _ in }
    public var showInactiveChannels: (any AccountContextProtocol, InactiveChannelsReason) -> Void = { _, _ in }
    public var reportContent: (any AccountContextProtocol, ReportContentSubject, String) -> Void = { _, _, _ in }
    public var showSponsoredReport: (any AccountContextProtocol, Window, String, String?, String, SponsoredReportPage, @escaping (SponsoredReportOption) -> Signal<SponsoredReportPage?, NoError>) -> Void = { _, _, _, _, _, _, _ in }
    public var makeRecentSessionsController: (any AccountContextProtocol) -> ViewController? = { _ in nil }
    public var makeProxyListController: (any AccountContextProtocol, @escaping ([ProxyServerSettings]) -> Void, @escaping (ViewController) -> Void) -> ViewController? = { _, _, _ in nil }
    public var makeInviteLinksController: (any AccountContextProtocol, PeerId, Bool) -> ViewController? = { _, _, _ in nil }
    public var makeRequestJoinMembersController: (any AccountContextProtocol, PeerId, PeerInvitationImportersContext, @escaping () -> Void) -> ViewController? = { _, _, _, _ in nil }
    public var showInvitePrivacyLimited: (any AccountContextProtocol, PeerId, [PeerId], [TelegramForbiddenInvitePeer]) -> Void = { _, _, _, _ in }
    public var openStoryStats: (any AccountContextProtocol, EngineStoryItem, EnginePeer) -> Void = { _, _, _ in }
    public var showBoostInfo: (any AccountContextProtocol, Window, Peer, ChannelBoostStatus, MyBoostStatus?, BoostInfoSource, TelegramPresentationTheme?) -> Void = { _, _, _, _, _, _, _ in }
    public var hasFeatureModal: (FeatureModalKind, ModalViewController?) -> Bool = { _, _ in false }
    public var makeVerifyAgeController: (any AccountContextProtocol) -> ModalViewController? = { _ in nil }
    public var makeCalendarController: (Window, Date, Int, Bool, @escaping (Date) -> Void) -> ViewController? = { _, _, _, _, _ in nil }
    public var makeSelectCountriesController: (any AccountContextProtocol, [Country], @escaping ([Country]) -> Void) -> ModalViewController? = { _, _, _ in nil }
    public var makePaymentsCheckoutController: (any AccountContextProtocol, BotPaymentInvoiceSource, TelegramMediaInvoice, ((PaymentCheckoutResult) -> Void)?) -> ModalViewController? = { _, _, _, _ in nil }
    public var emptyChatControllerType: () -> ViewController.Type? = { nil }
    public var openInstantView: (any AccountContextProtocol, String, TelegramMediaWebpage) -> Void = { _, _, _ in }
    public var requestUserLocation: () -> Signal<UserLocationRequestResult, NoError> = { .single(.disabled) }
    public var fullExportRowTitle: () -> String = { "" }
    public var fullExportRowInfo: () -> String = { "" }
    public var showFullExportModal: (any AccountContextProtocol) -> Void = { _ in }
    public var makeGigagroupLandingController: (any AccountContextProtocol, PeerId) -> ModalViewController? = { _, _ in nil }
    public var openJoinChatBotWebView: (any AccountContextProtocol, PeerId, String?, Int64, PeerId?) -> Void = { _, _, _, _, _ in }
    public var makeGroupCallAvatarMenuItem: (Peer, any AccountContextProtocol) -> ContextMenuItem? = { _, _ in nil }
    public var selectGroupCallJoiner: (any AccountContextProtocol, PeerId, @escaping (PeerId, Date?, Bool) -> Void) -> Void = { _, _, _ in }
    public var makeLinkInvitationController: (any AccountContextProtocol, PeerId) -> ViewController? = { _, _ in nil }
    public var makeTwoStepAccessController: (any AccountContextProtocol, @escaping (ViewController, Bool, Bool) -> Void) -> ViewController? = { _, _ in nil }
    public var createSupergroup: (any AccountContextProtocol, String) -> Signal<PeerId?, NoError> = { _, _ in .single(nil) }
    public var shareLink: (any AccountContextProtocol, Window, String) -> Void = { _, _, _ in }
    public var makeChannelAdminController: (any AccountContextProtocol, PeerId, PeerId, ChannelParticipant?, @escaping (TelegramChatAdminRights?) -> Void, @escaping (PeerId, @escaping () -> Void) -> Void) -> ModalViewController? = { _, _, _, _, _, _ in nil }
    public var applyGroupCallResult: (any SharedAccountContextProtocol, AnyObject) -> Void = { _, _ in }
    public var fileSizeLimitExceed: (any AccountContextProtocol, Int64) -> Bool = { _, _ in true }
    public var showFileLimit: (any AccountContextProtocol, Int64?) -> Void = { _, _ in }
    public var makePreviewSender: ([URL], AnyObject, Bool, NSAttributedString?, TelegramPresentationTheme?) -> ModalViewController? = { _, _, _, _, _ in nil }
    public var makeArchiveSettingsController: (any AccountContextProtocol, GlobalPrivacySettings?, @escaping (GlobalPrivacySettings) -> Void) -> ViewController? = { _, _, _ in nil }
    public var updateAccountBirthday: (Date, any AccountContextProtocol) -> Void = { _, _ in }

    public init() {}

    private static var installed: FeatureNavigationHooks?

    public static var shared: FeatureNavigationHooks {
        return installed ?? FeatureNavigationHooks()
    }

    public static var isInstalled: Bool {
        return installed != nil
    }

    public static func install(_ hooks: FeatureNavigationHooks) {
        installed = hooks
    }
}
