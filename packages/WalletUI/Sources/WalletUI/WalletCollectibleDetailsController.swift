import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import InputDataUI
import Localization
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import CurrencyFormat
import WalletContext

private let _id_collectible_header = InputDataIdentifier("_id_collectible_header")
private let _id_collectible_details = InputDataIdentifier("_id_collectible_details")
private let _id_collectible_actions = InputDataIdentifier("_id_collectible_actions")
private let _id_collectible_previous = InputDataIdentifier("_id_collectible_previous")
private let _id_collectible_next = InputDataIdentifier("_id_collectible_next")

private let walletCollectibleGiftTraitKeys = ["model", "symbol", "backdrop"]

private struct WalletCollectibleGiftTrait: Equatable {
    let name: String
    let rarity: StarGift.UniqueGift.Attribute.Rarity?
}

enum WalletCollectibleTransferRoute: Equatable {
    case transfer
    case restoreSigningAccess
    case enterRecoveryPhrase
    case unavailable
}

@available(macOS 10.15, *)
func walletCollectibleTransferRoute(_ phase: WalletContext.Phase) -> WalletCollectibleTransferRoute {
    guard case let .wallet(info) = phase else {
        return .unavailable
    }
    if info.canSign {
        return .transfer
    } else if info.canExportPhrase {
        return .restoreSigningAccess
    } else {
        return .enterRecoveryPhrase
    }
}

@available(macOS 10.15, *)
private func walletCollectibleKindText(_ kind: WalletContext.Collectible.Kind) -> String {
    switch kind {
    case .gift:
        return strings().walletCollectibleDetailsControllerCollectibleGift
    case .username:
        return strings().walletCollectibleDetailsControllerUsername
    case .anonymousNumber:
        return strings().walletCollectibleDetailsControllerAnonymousNumber
    case .other:
        return strings().walletCollectibleDetailsControllerCollectible
    }
}

@available(macOS 10.15, *)
private struct WalletCollectibleDetailsState: Equatable {
    var collectibles: [WalletContext.Collectible]
    var currentAddress: String
    var collectiblesState: WalletContext.CollectiblesState
    var requestedPage: WalletContext.CollectiblesState.PageId? = nil
    var failedPage: WalletContext.CollectiblesState.PageId? = nil
    var giftTraits: [String: WalletCollectibleGiftTrait] = [:]
    var giftValue: String? = nil
    var ownerAvatar: CGImage? = nil

    var currentIndex: Int {
        collectibles.firstIndex(where: { $0.address == currentAddress }) ?? 0
    }

    var collectible: WalletContext.Collectible? {
        collectibles.indices.contains(currentIndex) ? collectibles[currentIndex] : nil
    }

    mutating func updateCollectiblesState(_ state: WalletContext.CollectiblesState) {
        if let requestedPage = self.requestedPage, state.nextPage != requestedPage || !state.canLoadMore {
            self.requestedPage = nil
            self.failedPage = nil
        }
        self.collectiblesState = state
    }

    mutating func resetFailedPageIfNeeded() {
        if self.failedPage == self.collectiblesState.nextPage {
            self.requestedPage = nil
            self.failedPage = nil
        }
    }
}

@available(macOS 10.15, *)
func walletCollectiblesPageToRequest(index: Int, count: Int, state: WalletContext.CollectiblesState, requestedPage: WalletContext.CollectiblesState.PageId?, failedPage: WalletContext.CollectiblesState.PageId?, hasActiveOperation: Bool) -> WalletContext.CollectiblesState.PageId? {
    guard count > 0,
          index >= max(0, count - 2),
          let page = state.nextPage,
          !state.isRefreshing,
          !state.isLoadingMore,
          state.error == nil || failedPage == nil,
          !hasActiveOperation else {
        return nil
    }
    guard requestedPage != page else {
        return nil
    }
    return page
}

private final class WalletCollectibleDetailsArguments {
    let previous: () -> Void
    let next: () -> Void
    let transfer: () -> Void
    let wear: () -> Void
    let sell: () -> Void

    init(previous: @escaping () -> Void, next: @escaping () -> Void, transfer: @escaping () -> Void, wear: @escaping () -> Void, sell: @escaping () -> Void) {
        self.previous = previous
        self.next = next
        self.transfer = transfer
        self.wear = wear
        self.sell = sell
    }
}

@available(macOS 10.15, *)
final class WalletCollectibleHeroRowItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    let environment: WalletUIEnvironment
    fileprivate let collectible: WalletContext.Collectible
    fileprivate let collectionAction: (() -> Void)?
    fileprivate let titleLayout: TextViewLayout
    fileprivate let collectionLayout: TextViewLayout?
    fileprivate let descriptionLayout: TextViewLayout?
    fileprivate let image: TelegramMediaWebFile?
    fileprivate let lottie: TelegramMediaWebFile?
    fileprivate private(set) var mediaSide: CGFloat = 0
    private var contentHeight: CGFloat = 0

    @available(macOS 10.15, *)
    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, environment: WalletUIEnvironment, collectible: WalletContext.Collectible, image: WalletNftFile?, lottie: WalletNftFile?, collectionAction: (() -> Void)?) {
        self.context = context
        self.environment = environment
        self.collectible = collectible
        self.collectionAction = collectionAction
        self.titleLayout = TextViewLayout(walletCollectibleNameAttributedString(collectible.name, font: .medium(20)), maximumNumberOfLines: 2, alignment: .center)
        let displaysCollection = collectible.kind == .gift || collectible.kind == .other
        if displaysCollection, let collectionName = collectible.collectionName?.trimmingCharacters(in: .whitespacesAndNewlines), !collectionName.isEmpty {
            self.collectionLayout = TextViewLayout(.initialize(string: collectionName, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1, alignment: .center)
        } else {
            self.collectionLayout = nil
        }
        if collectible.kind != .gift, let description = collectible.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            self.descriptionLayout = TextViewLayout(.initialize(string: description, color: theme.colors.grayText, font: .normal(.text)), alignment: .center)
        } else {
            self.descriptionLayout = nil
        }
        self.image = walletCollectibleWebFile(image)
        self.lottie = walletCollectibleWebFile(lottie)
        super.init(initialSize, stableId: stableId, viewType: .legacy)
    }

    override var height: CGFloat {
        return contentHeight
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        mediaSide = min(164, max(0, blockWidth - 64))
        let textWidth = max(0, blockWidth - 48)
        titleLayout.measure(width: textWidth)
        collectionLayout?.measure(width: textWidth)
        descriptionLayout?.measure(width: textWidth)
        contentHeight = mediaSide + 18 + titleLayout.layoutSize.height
        if let collectionLayout {
            contentHeight += 6 + collectionLayout.layoutSize.height
        }
        if let descriptionLayout {
            contentHeight += 12 + descriptionLayout.layoutSize.height
        }
        return true
    }

    override func viewClass() -> AnyClass {
        return WalletCollectibleHeroRowView.self
    }
}

@available(macOS 10.15, *)
private final class WalletCollectibleHeroRowView: TableRowView {
    private let placeholderView = View(frame: .zero)
    private let imageView = TransformImageView(frame: .zero)
    private let lottieView = Control(frame: .zero)
    private let titleView = TextView()
    private let collectionButton = Control()
    private let collectionView = TextView()
    private let collectionNextView = ImageView()
    private let descriptionView = TextView()
    private let imageFetchDisposable = MetaDisposable()
    private let fetchDisposable = MetaDisposable()
    private let lottieDisposable = MetaDisposable()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        placeholderView.layer?.cornerRadius = 16
        lottieView.layer?.cornerRadius = 16
        lottieView.layer?.masksToBounds = true
        for textView in [titleView, collectionView, descriptionView] {
            textView.userInteractionEnabled = false
            textView.isSelectable = false
        }
        collectionNextView.isEventLess = true
        collectionButton.addSubview(collectionView)
        collectionButton.addSubview(collectionNextView)
        addSubview(placeholderView)
        addSubview(imageView)
        addSubview(lottieView)
        addSubview(titleView)
        addSubview(collectionButton)
        addSubview(descriptionView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        imageFetchDisposable.dispose()
        fetchDisposable.dispose()
        lottieDisposable.dispose()
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func updateColors() {
        placeholderView.backgroundColor = theme.colors.grayForeground
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        let previousItem = self.item as? WalletCollectibleHeroRowItem
        super.set(item: item, animated: animated)
        guard let item = item as? WalletCollectibleHeroRowItem else {
            return
        }
        titleView.update(item.titleLayout)

        collectionButton.removeAllHandlers()
        if let collectionLayout = item.collectionLayout {
            collectionView.update(collectionLayout)
            collectionButton.isHidden = false
            if item.collectionAction != nil {
                collectionNextView.isHidden = false
                collectionNextView.image = theme.icons.generalNext
                collectionNextView.sizeToFit()
                collectionButton.userInteractionEnabled = true
                collectionButton.scaleOnClick = true
                collectionButton.set(cursor: .pointingHand, for: .Hover)
                collectionButton.set(handler: { _ in item.collectionAction?() }, for: .Click)
            } else {
                collectionNextView.isHidden = true
                collectionButton.userInteractionEnabled = false
                collectionButton.scaleOnClick = false
                collectionButton.set(cursor: .arrow, for: .Hover)
            }
        } else {
            collectionButton.isHidden = true
        }
        if let descriptionLayout = item.descriptionLayout {
            descriptionView.update(descriptionLayout)
            descriptionView.isHidden = false
        } else {
            descriptionView.isHidden = true
        }

        imageFetchDisposable.set(nil)
        imageView.clear()
        imageView.isHidden = true
        if let image = item.image {
            imageView.isHidden = false
            imageView.set(arguments: TransformImageArguments(corners: ImageCorners(radius: 16), imageSize: NSMakeSize(item.mediaSide, item.mediaSide), boundingSize: NSMakeSize(item.mediaSide, item.mediaSide), intrinsicInsets: NSEdgeInsetsZero))
            imageView.setSignal(item.environment.webFilePhoto( photo: image, scale: backingScaleFactor, useActualDimensions: true))
            imageFetchDisposable.set(fetchedMediaResource(mediaBox: item.context.account.postbox.mediaBox, userLocation: .other, userContentType: .other, reference: MediaResourceReference.standalone(resource: image.resource)).start())
        }

        if previousItem?.context.account !== item.context.account || previousItem?.lottie?.resource.id != item.lottie?.resource.id {
            fetchDisposable.set(nil)
            lottieDisposable.set(nil)
            item.environment.setCollectibleAnimation(in: lottieView, contents: nil, key: "", size: NSMakeSize(item.mediaSide, item.mediaSide))
            lottieView.isHidden = true
            if let lottie = item.lottie {
                fetchDisposable.set(fetchedMediaResource(mediaBox: item.context.account.postbox.mediaBox, userLocation: .other, userContentType: .other, reference: MediaResourceReference.standalone(resource: lottie.resource)).start())
                lottieDisposable.set((item.context.account.postbox.mediaBox.resourceData(lottie.resource, attemptSynchronously: true)
                |> filter { $0.complete }
                |> take(1)
                |> deliverOnMainQueue).start(next: { [weak self] data in
                    guard let self, let item = self.item as? WalletCollectibleHeroRowItem,
                          item.lottie?.resource.id == lottie.resource.id,
                          data.size <= Int64(5 * 1024 * 1024),
                          let fileData = try? Data(contentsOf: URL(fileURLWithPath: data.path), options: .mappedIfSafe),
                          let contents = walletCollectibleLottieData(fileData) else {
                        return
                    }
                    item.environment.setCollectibleAnimation(in: self.lottieView, contents: contents, key: "wallet_collectible_hero_\(item.collectible.address)_\(contents.hashValue)", size: NSMakeSize(item.mediaSide, item.mediaSide))
                    self.lottieView.isHidden = false
                }))
            }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? WalletCollectibleHeroRowItem else {
            return
        }
        let mediaFrame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - item.mediaSide) / 2), 0, item.mediaSide, item.mediaSide)
        placeholderView.frame = mediaFrame
        imageView.frame = mediaFrame
        lottieView.frame = mediaFrame
        titleView.centerX(y: mediaFrame.maxY + 18)
        var textY = titleView.frame.maxY
        if item.collectionLayout != nil {
            let chevronWidth = collectionNextView.isHidden ? 0 : collectionNextView.frame.width + 2
            collectionButton.setFrameSize(NSMakeSize(collectionView.frame.width + chevronWidth, collectionView.frame.height))
            collectionButton.centerX(y: textY + 6)
            collectionView.setFrameOrigin(.zero)
            collectionNextView.centerY(x: collectionView.frame.maxX + 2)
            textY = collectionButton.frame.maxY
        }
        if item.descriptionLayout != nil {
            descriptionView.centerX(y: textY + 12)
        }
    }
}

private final class WalletCollectibleActionRowItem: GeneralRowItem {
    fileprivate enum Action: CaseIterable {
        case transfer
        case wear
        case sell

        var title: String {
            switch self {
            case .transfer: return strings().walletCollectibleDetailsControllerActionTransfer
            case .wear: return strings().walletCollectibleDetailsControllerActionWear
            case .sell: return strings().walletCollectibleDetailsControllerActionSell
            }
        }

        var image: NSImage? {
            switch self {
            case .transfer: return NSImage(named: "Icon_NFT_Transfer")
            case .wear: return NSImage(named: "Icon_NFT_Wear")
            case .sell: return NSImage(named: "Icon_Nft_Sell")
            }
        }
    }

    fileprivate let actions: [Action]
    fileprivate let callbacks: [Action: () -> Void]

    @available(macOS 10.15, *)
    init(_ initialSize: NSSize, stableId: AnyHashable, collectible: WalletContext.Collectible, arguments: WalletCollectibleDetailsArguments) {
        self.actions = [.transfer, .sell]
        self.callbacks = [.transfer: arguments.transfer, .wear: arguments.wear, .sell: arguments.sell]
        super.init(initialSize, stableId: stableId, viewType: .legacy)
    }

    override var height: CGFloat {
        return 88
    }

    override func viewClass() -> AnyClass {
        return WalletCollectibleActionRowView.self
    }
}

private final class WalletCollectibleActionControl: Control {
    private let imageView = ImageView()
    private let titleView = TextView()
    private var callback: (() -> Void)?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.cornerRadius = 20
        imageView.contentGravity = .center
        imageView.animates = true
        imageView.isEventLess = true
        titleView.isEventLess = true
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        controlOpacityEventIgnored = true
        addSubview(imageView)
        addSubview(titleView)

        set(handler: { control in
            control.change(opacity: 0.8, animated: true)
        }, for: .Highlight)
        set(handler: { control in
            control.change(opacity: 1.0, animated: true)
        }, for: .Normal)
        set(handler: { control in
            control.change(opacity: 1.0, animated: true)
        }, for: .Hover)
        set(handler: { [weak self] _ in
            self?.callback?()
        }, for: .Click)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(action: WalletCollectibleActionRowItem.Action, callback: @escaping () -> Void) {
        self.callback = callback
        backgroundColor = theme.colors.background
        imageView.image = action.image?.precomposed(walletClassicAccent)
        imageView.sizeToFit()
        let titleLayout = TextViewLayout(.initialize(string: action.title, color: walletClassicAccent, font: .normal(.text)), maximumNumberOfLines: 1, alignment: .center)
        titleLayout.measure(width: 125)
        titleView.update(titleLayout)
    }

    func reset() {
        callback = nil
    }

    override func layout() {
        super.layout()
        imageView.centerX(y: 5)
        titleView.centerX(y: frame.height - titleView.frame.height - 11)
    }
}

private final class WalletCollectibleActionRowView: TableRowView {
    private var actionViews: [WalletCollectibleActionControl] = []

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? WalletCollectibleActionRowItem else {
            return
        }
        while actionViews.count < item.actions.count {
            let view = WalletCollectibleActionControl(frame: .zero)
            actionViews.append(view)
            addSubview(view)
        }
        for (index, view) in actionViews.enumerated() {
            guard index < item.actions.count else {
                view.reset()
                view.isHidden = true
                continue
            }
            let action = item.actions[index]
            view.isHidden = false
            view.update(action: action, callback: item.callbacks[action] ?? {})
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? WalletCollectibleActionRowItem else {
            return
        }
        let sideInset: CGFloat = 20
        let spacing: CGFloat = 10
        let width = floor((frame.width - sideInset * 2 - spacing * CGFloat(item.actions.count - 1)) / CGFloat(item.actions.count))
        for (index, view) in actionViews.enumerated() where index < item.actions.count {
            view.frame = NSMakeRect(sideInset + CGFloat(index) * (width + spacing), 28, width, 60)
        }
    }
}

func walletCollectibleExplorerUrl(explorerUrl: String, address: String) -> String? {
    guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), !encodedAddress.isEmpty else {
        return nil
    }
    let baseUrl = explorerUrl.hasSuffix("/") ? explorerUrl : explorerUrl + "/"
    return baseUrl + encodedAddress
}

@available(macOS 10.15, *)
private func walletCollectibleExplorerUrl(context: any AccountContextProtocol, environment: WalletUIEnvironment, address: String) -> String? {
    return walletCollectibleExplorerUrl(explorerUrl: WalletConfiguration.with(appConfiguration: context.appConfiguration).explorerUrl, address: address)
}

@available(macOS 10.15, *)
private func walletCollectibleFragmentUrl(_ collectible: WalletContext.Collectible) -> String? {
    let path: String
    var value: String
    switch collectible.kind {
    case .username:
        path = "username"
        value = collectible.name.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        if value.lowercased().hasSuffix(".t.me") {
            value.removeLast(".t.me".count)
        }
    case .anonymousNumber:
        path = "number"
        value = collectible.name.filter(\.isNumber)
    case .gift:
        path = "gift"
        value = collectible.giftSlug ?? ""
    case .other:
        return nil
    }
    guard !value.isEmpty else {
        return nil
    }
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#%")
    guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
        return nil
    }
    return "https://fragment.com/\(path)/\(encoded)"
}

@available(macOS 10.15, *)
private func walletCollectibleDetailsEntries(_ state: WalletCollectibleDetailsState, context: any AccountContextProtocol, environment: WalletUIEnvironment, arguments: WalletCollectibleDetailsArguments) -> [InputDataEntry] {
    guard let collectible = state.collectible else {
        return []
    }
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0
    entries.append(.sectionId(sectionId, type: .customModern(12)))
    sectionId += 1
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_collectible_header, equatable: .init(collectible), comparable: nil, item: { initialSize, stableId in
        WalletCollectibleHeroRowItem(initialSize, stableId: stableId, context: context, environment: environment, collectible: collectible, image: collectible.image, lottie: collectible.lottie, collectionAction: collectible.collectionUrl.map { url in
            { environment.openExternalURL(url) }
        })
    }))
    index += 1

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_collectible_actions, equatable: .init("\(collectible.address)_\(collectible.kind)"), comparable: nil, item: { initialSize, stableId in
        WalletCollectibleActionRowItem(initialSize, stableId: stableId, collectible: collectible, arguments: arguments)
    }))
    index += 1

    var rows: [WalletDetailsTableRowItem.Row] = [
        .init(label: strings().walletCollectibleDetailsControllerType, value: walletCollectibleKindText(collectible.kind)),
        .init(label: strings().walletCollectibleDetailsControllerAddress, value: collectible.address, isAddress: true, onClick: { walletCopyAddress(collectible.address, environment: environment, window: context.window) })
    ]
    if let collectionName = collectible.collectionName, !collectionName.isEmpty {
        rows.append(.init(label: strings().walletCollectibleDetailsControllerCollection, value: collectionName, onClick: collectible.collectionUrl.map { url in { environment.openExternalURL(url) } }))
    }
    if collectible.kind == .gift {
        rows.append(.init(label: strings().walletCollectibleDetailsControllerOwner, value: strings().walletCollectibleDetailsControllerOwnerYou, icon: state.ownerAvatar, valueColor: walletClassicAccent))
    }
    var remainingAttributeKeys = Set(collectible.attributes.keys)
    if collectible.kind == .gift {
        let traitLabels: [String: String] = ["model": strings().walletCollectibleDetailsControllerModel, "symbol": strings().walletCollectibleDetailsControllerSymbol, "backdrop": strings().walletCollectibleDetailsControllerBackdrop]
        for key in walletCollectibleGiftTraitKeys {
            remainingAttributeKeys.remove(key)
            let trait = state.giftTraits[key]
            let value = trait?.name ?? collectible.attributes[key] ?? "—"
            var badge: (text: String, color: NSColor?)? = nil
            if let rarity = trait?.rarity {
                badge = environment.rarityBadge(rarity)
            }
            rows.append(.init(label: traitLabels[key] ?? key.capitalized, value: value, badge: badge))
        }
    }
    for key in remainingAttributeKeys.sorted() {
        rows.append(.init(label: key.capitalized, value: collectible.attributes[key] ?? "—"))
    }
    if collectible.kind == .gift {
    }
    let rowsSignature = rows.map { "\($0.label):\($0.value):\($0.badge?.text ?? "")" }.joined(separator: "|") + "|avatar:\(state.ownerAvatar != nil)"
    entries.append(.sectionId(sectionId, type: .customModern(30)))
    sectionId += 1
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_collectible_details, equatable: .init(rowsSignature), comparable: nil, item: { initialSize, stableId in
        WalletDetailsTableRowItem(initialSize, stableId: stableId, rows: rows, viewType: .singleItem)
    }))
    index += 1

    if state.collectibles.count > 1 {
        entries.append(.sectionId(sectionId, type: .customModern(12)))
        sectionId += 1
        let currentIndex = state.currentIndex
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_collectible_previous, equatable: .init(currentIndex > 0), comparable: nil, item: { initialSize, stableId in
            GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().walletCollectibleDetailsControllerPreviousCollectible, nameStyle: currentIndex > 0 ? ControlStyle(font: .normal(.title), foregroundColor: walletClassicAccent) : ControlStyle(font: .normal(.title), foregroundColor: theme.colors.grayText), type: .none, viewType: .firstItem, action: arguments.previous)
        }))
        index += 1
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_collectible_next, equatable: .init(currentIndex < state.collectibles.count - 1), comparable: nil, item: { initialSize, stableId in
            GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().walletCollectibleDetailsControllerNextCollectible, nameStyle: currentIndex < state.collectibles.count - 1 ? ControlStyle(font: .normal(.title), foregroundColor: walletClassicAccent) : ControlStyle(font: .normal(.title), foregroundColor: theme.colors.grayText), type: .none, viewType: .lastItem, action: arguments.next)
        }))
    }

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1

    return entries
}

@available(macOS 10.15, *)
public func WalletCollectibleDetailsController(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, collectible: WalletContext.Collectible, collectibleSent: ((String) -> Void)? = nil) -> InputDataModalController {
    let initialCollectibles = walletContext.stateValue.collectibles.items.contains(where: { $0.address == collectible.address }) ? walletContext.stateValue.collectibles.items : [collectible] + walletContext.stateValue.collectibles.items
    let initialState = WalletCollectibleDetailsState(
        collectibles: initialCollectibles,
        currentAddress: collectible.address,
        collectiblesState: walletContext.stateValue.collectibles
    )
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((WalletCollectibleDetailsState) -> WalletCollectibleDetailsState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }
    let disposables = DisposableSet()
    let loadMoreDisposable = MetaDisposable()
    let giftDisposable = MetaDisposable()
    disposables.add(loadMoreDisposable)
    disposables.add(giftDisposable)

    var isActive = true
    var close: (() -> Void)?
    let loadMoreIfNeeded: () -> Void = {
        let state = stateValue.with { $0 }
        guard let page = walletCollectiblesPageToRequest(index: state.currentIndex, count: state.collectibles.count, state: state.collectiblesState, requestedPage: state.requestedPage, failedPage: state.failedPage, hasActiveOperation: walletContext.stateValue.activeOperation != nil) else {
            return
        }
        updateState { current in
            var current = current
            current.requestedPage = page
            return current
        }
        loadMoreDisposable.set((walletContext.loadMoreCollectibles()
        |> deliverOnMainQueue).start(error: { _ in
            updateState { current in
                var current = current
                if current.requestedPage == page {
                    current.failedPage = page
                }
                return current
            }
        }))
    }
    var fetchGiftTraits: (() -> Void)?
    let previous = {
        updateState { current in
            var current = current
            current.resetFailedPageIfNeeded()
            guard current.currentIndex > 0 else { return current }
            current.currentAddress = current.collectibles[current.currentIndex - 1].address
            return current
        }
        fetchGiftTraits?()
    }
    let next = {
        updateState { current in
            var current = current
            current.resetFailedPageIfNeeded()
            guard current.currentIndex + 1 < current.collectibles.count else { return current }
            current.currentAddress = current.collectibles[current.currentIndex + 1].address
            return current
        }
        fetchGiftTraits?()
        loadMoreIfNeeded()
    }
    let presentTransfer: (WalletContext.Collectible) -> Void = { current in
        showModal(with: makeWalletRecipientController(context: context, environment: environment, walletContext: walletContext, initialQuery: nil, initialAmount: nil, mode: .collectible(current), onSuccess: {
            collectibleSent?(current.address)
            close?()
        }), for: context.window)
    }
    let restoreAuthorization = WalletFlowAuthorization(walletContext: walletContext, reason: walletRestoreFlowReason)
    let restoreDisposable = MetaDisposable()
    disposables.add(restoreDisposable)
    var transfer: (() -> Void)?
    transfer = {
        guard isActive, let current = stateValue.with({ $0.collectible }) else { return }
        switch walletCollectibleTransferRoute(walletContext.stateValue.phase) {
        case .transfer:
            restoreAuthorization.end()
            presentTransfer(current)
        case .restoreSigningAccess:
            restoreDisposable.set(walletRestoreSigningAccess(context: context, environment: environment, window: context.window, walletContext: walletContext, authorization: restoreAuthorization, retry: {
                transfer?()
            }, next: {
                guard isActive, stateValue.with({ $0.collectible?.address }) == current.address else { return }
                presentTransfer(current)
            }, failed: {}))
        case .enterRecoveryPhrase:
            showModal(with: WalletImportController(context: context, environment: environment, walletContext: walletContext, mode: .enterRecoveryPhrase, onImported: {}), for: context.window)
        case .unavailable:
            environment.showModalText(for: context.window, text: strings().walletCollectibleDetailsControllerStillSyncing)
        }
    }
    let wear = {
        guard let current = stateValue.with({ $0.collectible }), current.kind == .gift, let slug = current.giftSlug else { return }
        _ = showModalProgress(signal: context.engine.payments.getUniqueStarGift(slug: slug), for: context.window).start(next: { gift in
            environment.openGift(gift)
        })
    }
    let sell = {
        guard let current = stateValue.with({ $0.collectible }), let url = walletCollectibleFragmentUrl(current) else { return }
        environment.openExternalURL(url)
    }
    let arguments = WalletCollectibleDetailsArguments(previous: previous, next: next, transfer: { transfer?() }, wear: wear, sell: sell)

    disposables.add((walletContext.state
    |> deliverOnMainQueue).start(next: { walletState in
        updateState { current in
            var current = current
            var items = walletState.collectibles.items
            if !items.contains(where: { $0.address == current.currentAddress }), let selected = current.collectible {
                items.insert(selected, at: min(current.currentIndex, items.count))
            }
            current.collectibles = items
            current.updateCollectiblesState(walletState.collectibles)
            return current
        }
        loadMoreIfNeeded()
    }))

    fetchGiftTraits = {
        updateState { current in
            var current = current
            current.giftTraits = [:]
            current.giftValue = nil
            return current
        }
        guard let current = stateValue.with({ $0.collectible }), current.kind == .gift, let slug = current.giftSlug else {
            giftDisposable.set(nil)
            return
        }
        giftDisposable.set((context.engine.payments.getUniqueStarGift(slug: slug)
        |> deliverOnMainQueue).start(next: { gift in
            var traits: [String: WalletCollectibleGiftTrait] = [:]
            for attribute in gift.attributes {
                switch attribute {
                case let .model(name, _, rarity, _): traits["model"] = .init(name: name, rarity: rarity)
                case let .pattern(name, _, rarity): traits["symbol"] = .init(name: name, rarity: rarity)
                case let .backdrop(name, _, _, _, _, _, rarity): traits["backdrop"] = .init(name: name, rarity: rarity)
                default: break
                }
            }
            updateState { current in
                var current = current
                current.giftTraits = traits
                var valueParts: [String] = []
                if let amount = gift.valueAmount, let currency = gift.valueCurrency {
                    valueParts.append(formatCurrencyAmount(amount, currency: currency))
                }
                if let usdAmount = gift.valueUsdAmount {
                    valueParts.append("~\(formatCurrencyAmount(usdAmount, currency: "USD"))")
                }
                current.giftValue = valueParts.isEmpty ? nil : valueParts.joined(separator: " ")
                return current
            }
        }, error: { _ in }))
    }
    fetchGiftTraits?()

    if let myPeer = context.myPeer {
        disposables.add((environment.ownerAvatar(myPeer, size: NSMakeSize(WalletDetailsTableRowItem.iconSize * System.backingScale, WalletDetailsTableRowItem.iconSize * System.backingScale), font: .avatar(8))
        |> deliverOnMainQueue).start(next: { image in
            updateState { current in
                var current = current
                current.ownerAvatar = image
                return current
            }
        }))
    }

    let signal = statePromise.get()
    |> deliverOnPrepareQueue
    |> map { state in
        InputDataSignalValue(entries: walletCollectibleDetailsEntries(state, context: context, environment: environment, arguments: arguments))
    }
    let controller = InputDataController(dataSignal: signal, title: strings().walletCollectibleDetailsControllerCollectible, hasDone: false)
    let interactions = ModalInteractions(acceptTitle: strings().walletCollectibleDetailsControllerOK, accept: { close?() }, singleButton: true, customTheme: { walletModalTheme })
    let result = WalletModalController(controller, modalInteractions: interactions, size: NSMakeSize(400, 0))
    close = { [weak result] in
        result?.close()
    }
    controller.willDisappear = { _ in
        isActive = false
        disposables.dispose()
    }
    let eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .swipe]) { [weak result] event in
        guard isActive, result?.modal != nil, event.window === context.window else {
            return event
        }
        switch event.type {
        case .keyDown:
            switch event.keyCode {
            case 123:
                previous()
                return nil
            case 124:
                next()
                return nil
            default:
                return event
            }
        case .swipe:
            if event.deltaX > 0 {
                previous()
                return nil
            } else if event.deltaX < 0 {
                next()
                return nil
            }
            return event
        default:
            return event
        }
    }
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { close?() })
    controller.rightModalHeader = ModalHeaderData(image: theme.icons.chatActionsActive, contextMenu: {
        guard let current = stateValue.with({ $0.collectible }), let url = walletCollectibleExplorerUrl(context: context, environment: environment, address: current.address) else { return [] }
        return [ContextMenuItem(strings().walletCollectibleDetailsControllerViewInExplorer, handler: { environment.openExternalURL(url) })]
    })
    controller.onDeinit = {
        NSEvent.removeMonitor(eventMonitor as Any)
        disposables.dispose()
        transfer = nil
    }
    return result
}
