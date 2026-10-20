import Foundation
import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import AvatarUI
import GeneralRows
import InputDataUI
import AlertsUI
import PremiumUI

private struct State: Equatable {
    var managerUsername: String
    var managerPeer: PeerEquatable?
    var botTitle: String
    var botUsername: String
    var usernameState: AddressNameAvailabilityState
}

private struct Arguments {
    let context: any AccountContextProtocol
    let dismiss: () -> Void
}

private let _id_header = InputDataIdentifier("_id_header")
private let _id_bot_name = InputDataIdentifier("_id_bot_name")
private let _id_bot_username = InputDataIdentifier("_id_bot_username")

private func checkBotUsernameSuffix(_ username: String) -> Bool {
    return username.lowercased().hasSuffix("bot")
}


private final class CreateBotHeaderItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let peer: Peer?
    fileprivate let titleLayout: TextViewLayout
    fileprivate let infoLayout: TextViewLayout
    fileprivate let dismiss: (() -> Void)?
    let photoSize = NSMakeSize(70, 70)

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, peer: Peer?, managerUsername: String, dismiss: (() -> Void)? = nil) {
        self.context = context
        self.peer = peer
        self.dismiss = dismiss

        self.titleLayout = TextViewLayout(.initialize(string: strings().createBotTitle, color: theme.colors.text, font: .medium(.header)), alignment: .center)

        let text = NSMutableAttributedString()
        _ = text.append(string: strings().createBotDescription(managerUsername), color: theme.colors.listGrayText, font: .normal(.text))
        text.detectBoldColorInString(with: .bold(.text))
        self.infoLayout = TextViewLayout(text, alignment: .center)

        super.init(initialSize, stableId: stableId)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        titleLayout.measure(width: width - 40)
        infoLayout.measure(width: width - 40)
        return true
    }

    override var height: CGFloat {
        return 10 + photoSize.height + 10 + titleLayout.layoutSize.height + 10 + infoLayout.layoutSize.height + 10
    }

    override func viewClass() -> AnyClass {
        return CreateBotHeaderView.self
    }
}

private final class CreateBotHeaderView: TableRowView {
    private let avatar = AvatarControl(font: .avatar(20))
    private let titleView = TextView()
    private let infoView = TextView()
    private var dismissButton: ImageButton?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        avatar.setFrameSize(NSMakeSize(70, 70))
        addSubview(avatar)
        addSubview(titleView)
        addSubview(infoView)

        avatar.userInteractionEnabled = false
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        infoView.userInteractionEnabled = false
        infoView.isSelectable = false
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? CreateBotHeaderItem else { return }

        if let peer = item.peer {
            avatar.setPeer(account: item.context.account, peer: peer)
        }

        titleView.update(item.titleLayout)
        infoView.update(item.infoLayout)

        if let dismiss = item.dismiss {
            let current: ImageButton
            if let view = self.dismissButton {
                current = view
            } else {
                current = ImageButton()
                current.scaleOnClick = true
                current.autohighlight = false
                self.dismissButton = current
                addSubview(current)
            }
            current.set(image: theme.icons.glass_close, for: .Normal)
            current.setGlassEffect(size: NSMakeSize(36, 36))
            current.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
            current.removeAllHandlers()
            current.set(handler: { _ in
                dismiss()
            }, for: .Click)
        } else {
            if let view = self.dismissButton {
                performSubviewRemoval(view, animated: animated)
                self.dismissButton = nil
            }
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()
        avatar.centerX(y: 15)
        titleView.centerX(y: avatar.frame.maxY + 10)
        infoView.centerX(y: titleView.frame.maxY + 10)
        dismissButton?.setFrameOrigin(NSMakePoint(10, 10))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return CreateBotHeaderItem(initialSize, stableId: stableId, context: arguments.context, peer: state.managerPeer?.peer, managerUsername: state.managerUsername, dismiss: arguments.dismiss)
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().createBotBotNameHeader), data: InputDataGeneralTextData(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.botTitle), error: nil, identifier: _id_bot_name, mode: .plain, data: InputDataRowData(viewType: .singleItem), placeholder: nil, inputPlaceholder: strings().createBotBotNamePlaceholder, filter: { $0 }, limit: 64))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1

    let usernameFilter: (String) -> String = { value in
        var set = CharacterSet.alphanumerics
        set.insert("_")
        return value.trimmingCharacters(in: set.inverted)
    }

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().createBotBotUsernameHeader), data: InputDataGeneralTextData(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.botUsername), error: nil, identifier: _id_bot_username, mode: .plain, data: InputDataRowData(viewType: .singleItem), placeholder: nil, inputPlaceholder: strings().createBotBotUsernamePlaceholder, filter: usernameFilter, limit: 32))
    index += 1

    let botSuffixOk = state.botUsername.isEmpty || checkBotUsernameSuffix(state.botUsername)

    if !botSuffixOk {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().createBotUsernameEndBot), data: InputDataGeneralTextData(color: theme.colors.redUI, viewType: .textBottomItem)))
        index += 1
    } else {
        switch state.usernameState {
        case .progress, .none:
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().createBotChecking), data: InputDataGeneralTextData(color: theme.colors.listGrayText, viewType: .textBottomItem, rightItem: InputDataGeneralTextRightData(isLoading: true, text: nil))))
            index += 1
        case let .fail(username, formatError, availability):
            if username?.length != 0 {
                let text: String
                if let formatError = formatError {
                    text = formatError.description
                } else {
                    text = availability.description(for: username ?? "", target: .username)
                }
                let color: NSColor
                switch availability {
                case .purchaseAvailable:
                    color = theme.colors.grayText
                default:
                    color = theme.colors.redUI
                }
                entries.append(.desc(sectionId: sectionId, index: index, text: .plain(text), data: InputDataGeneralTextData(color: color, viewType: .textBottomItem)))
                index += 1
            }
        case let .success(username):
            if username?.count != 0 {
                entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().usernameSettingsAvailable(username ?? "")), data: InputDataGeneralTextData(color: theme.colors.accent, viewType: .textBottomItem)))
                index += 1
            }
        }
    }

    entries.append(.desc(sectionId: sectionId, index: 1000, text: .plain(strings().createBotUsernameHint), data: InputDataGeneralTextData(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

public func CreateBotModalController(context: any AccountContextProtocol, managerUsername: String, botUsername: String, botTitle: String?) -> InputDataModalController {

    let actionsDisposable = DisposableSet()
    let availabilityDisposable = MetaDisposable()
    actionsDisposable.add(availabilityDisposable)

    let initialState = State(managerUsername: managerUsername, botTitle: botTitle ?? "", botUsername: botUsername, usernameState: .none(username: botUsername))

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var close: (() -> Void)?

    let arguments = Arguments(context: context, dismiss: {
        close?()
    })

    actionsDisposable.add((context.engine.peers.resolvePeerByName(name: managerUsername, referrer: nil)
        |> filter { $0 != .progress }
        |> map { $0.result }
        |> deliverOnMainQueue).start(next: { peer in
            if let peer = peer {
                updateState { current in
                    var current = current
                    current.managerPeer = .init(peer._asPeer())
                    return current
                }
            }
        }))

    if !botUsername.isEmpty, checkBotUsernameSuffix(botUsername) {
        let signal = context.engine.peers.validateAddressNameInteractive(domain: .bot(PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(0))), name: botUsername) |> map { state -> AddressNameAvailabilityState in
            switch state {
            case let .availability(availability):
                switch availability {
                case .available:
                    return .success(username: botUsername)
                case .invalid:
                    return .fail(username: botUsername, formatError: .invalidCharacters, availability: availability)
                case .taken:
                    return .fail(username: botUsername, formatError: nil, availability: availability)
                case .purchaseAvailable:
                    return .fail(username: botUsername, formatError: nil, availability: availability)
                }
            case let .invalidFormat(error):
                return .fail(username: botUsername, formatError: error, availability: .invalid)
            case .checking:
                return .progress(username: botUsername)
            }
        } |> deliverOnMainQueue

        availabilityDisposable.set(signal.start(next: { state in
            updateState { current in
                var current = current
                current.usernameState = state
                return current
            }
        }))
    }

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: "")

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().createBotCreate, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })

    controller.updateDatas = { data in
        let username = data[_id_bot_username]?.stringValue ?? ""
        updateState { current in
            var current = current
            if let title = data[_id_bot_name]?.stringValue {
                current.botTitle = title
            }
            current.botUsername = username
            current.usernameState = .none(username: username)
            return current
        }

        if username.isEmpty || !checkBotUsernameSuffix(username) {
            availabilityDisposable.set(nil)
            return .fail(.none)
        }

        let signal = context.engine.peers.validateAddressNameInteractive(domain: .bot(PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(0))), name: username) |> map { state -> AddressNameAvailabilityState in
            switch state {
            case let .availability(availability):
                switch availability {
                case .available:
                    return .success(username: username)
                case .invalid:
                    return .fail(username: username, formatError: .invalidCharacters, availability: availability)
                case .taken:
                    return .fail(username: username, formatError: nil, availability: availability)
                case .purchaseAvailable:
                    return .fail(username: username, formatError: nil, availability: availability)
                }
            case let .invalidFormat(error):
                return .fail(username: username, formatError: error, availability: .invalid)
            case .checking:
                return .progress(username: username)
            }
        } |> deliverOnMainQueue

        availabilityDisposable.set(signal.start(next: { state in
            updateState { current in
                var current = current
                current.usernameState = state
                return current
            }
        }))

        return .fail(.none)
    }

    controller.validateData = { _ in
        let state = stateValue.with { $0 }
        guard !state.botTitle.isEmpty, !state.botUsername.isEmpty else {
            return .fail(.none)
        }
        guard checkBotUsernameSuffix(state.botUsername) else {
            return .fail(.none)
        }
        guard let managerPeer = state.managerPeer else {
            return .fail(.none)
        }
        switch state.usernameState {
        case .success:
            break
        case let .none(username):
            if username?.isEmpty != false {
                return .fail(.none)
            }
        default:
            return .fail(.none)
        }
        return .fail(.doSomething(next: { f in
            let signal = context.engine.peers.createBot(name: state.botTitle, username: state.botUsername, managerPeerId: managerPeer.peer.id, viaDeeplink: true)
            _ = showModalProgress(signal: signal, for: context.window).start(next: { peer in
                close?()
                showModalText(for: context.window, text: strings().createBotSuccessInfo(state.managerUsername), title: strings().createBotSuccessTitle(state.botTitle))
                ComposeUIHooks.shared.navigateToChat(context.bindings.rootNavigation(), context, .peer(peer.id))
                f(.none)
            }, error: { error in
                switch error {
                case .limitExceeded:
                    let defaultLimit = context.appConfiguration.getGeneralValue("bots_create_limit_default", orElse: 20)
                    let premiumLimit = context.appConfiguration.getGeneralValue("bots_create_limit_premium", orElse: 40)
                    if context.isPremium {
                        showModalText(for: context.window, text: strings().createBotLimitReachedPremium(Int(premiumLimit)))
                    } else {
                        showModalText(for: context.window, text: strings().createBotLimitReached(Int(defaultLimit), Int(premiumLimit)), button: strings().premiumLimitIncrease, callback: { _ in
                            prem(with: PremiumBoardingController(context: context, source: .double_limits(.channels)), for: context.window)
                        })
                    }
                default:
                    alert(for: context.window, info: strings().unknownError)
                }
                f(.none)
            })
        }))
    }

    close = { [weak modalController] in
        modalController?.modal?.close()
    }

    return modalController
}
