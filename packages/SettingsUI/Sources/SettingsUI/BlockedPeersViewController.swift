
import Cocoa
import TGUIKit
import Postbox
import TelegramCore

import SwiftSignalKit
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import FoundationUtils
import AlertsUI
import InAppSettings
import AvatarUI
import ShortPeerRow
import LocalAnimations


private final class BlockedPeerControllerArguments {
    public let context: any AccountContextProtocol
    
    public let removePeer: (PeerId) -> Void
    public let openPeer:(PeerId) -> Void
    public init(context: any AccountContextProtocol, removePeer: @escaping (PeerId) -> Void, openPeer: @escaping(PeerId)->Void) {
        self.context = context
        self.removePeer = removePeer
        self.openPeer = openPeer
    }
}

private enum BlockedPeerEntryStableId: Hashable {
    case peer(PeerId)
    case empty
    case sectionId(Int32)
    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .peer(peerId):
            hasher.combine(peerId)
        case .empty:
            hasher.combine(0)
        case .sectionId:
            hasher.combine(1)
        }
    }

}

private enum BlockedPeerEntry: Identifiable, Comparable {
    case section(Int32)
    case peerItem(Int32, Int32, Peer, ShortPeerDeleting?, Bool, GeneralViewType)
    case empty(Bool)
    public var stableId: BlockedPeerEntryStableId {
        switch self {
        case let .peerItem(_, _, peer, _, _, _):
            return .peer(peer.id)
        case .empty:
            return .empty
        case let .section(id):
            return .sectionId(id)
        }
    }
    
    public static func ==(lhs: BlockedPeerEntry, rhs: BlockedPeerEntry) -> Bool {
        switch lhs {
        case let .peerItem(lhsSectionId, lhsIndex, lhsPeer, lhsEditing, lhsEnabled, lhsViewType):
            if case let .peerItem(rhsSectionId, rhsIndex, rhsPeer, rhsEditing, rhsEnabled, rhsViewType) = rhs {
                if lhsIndex != rhsIndex {
                    return false
                }
                if !lhsPeer.isEqual(rhsPeer) {
                    return false
                }
                if lhsSectionId != rhsSectionId {
                    return false
                }
                if lhsEditing != rhsEditing {
                    return false
                }
                if lhsEnabled != rhsEnabled {
                    return false
                }
                if rhsViewType != lhsViewType {
                    return false
                }
                return true
            } else {
                return false
            }
        case let .empty(loading):
            if case .empty(loading) = rhs {
                return true
            } else {
                return false
            }
        case let .section(id):
            if case .section(id) = rhs {
                return true
            } else {
                return false
            }
        }
    }
    
    public var index: Int32 {
        switch self {
        case .empty:
            return 0
        case let .peerItem(sectionId, index, _, _, _, _):
            return (sectionId * 1000) + index
        case let .section(sectionId):
            return (sectionId * 1000) + sectionId
        }
    }
    
    public static func <(lhs: BlockedPeerEntry, rhs: BlockedPeerEntry) -> Bool {
        return lhs.index < rhs.index
    }
    
    public func item(_ arguments: BlockedPeerControllerArguments, initialSize:NSSize) -> TableRowItem {
        switch self {
        case let .peerItem(_, _, peer, editing, enabled, viewType):
            
            let interactionType:ShortPeerItemInteractionType
            if let editing = editing {
                
                interactionType = .deletable(onRemove: { peerId in
                    arguments.removePeer(peerId)
                }, deletable: editing.editable)
            } else {
                interactionType = .plain
            }
            
            return ShortPeerRowItem(initialSize, peer: peer, account: arguments.context.account, context: arguments.context, stableId: stableId, enabled: enabled, height: 46, photoSize: NSMakeSize(32, 32), inset: NSEdgeInsets(left: 20, right: 20), interactionType: interactionType, generalType: .none, viewType: viewType, action: {
                arguments.openPeer(peer.id)
            }, contextMenuItems: {
                if case .plain = interactionType {
                    return .single([ContextMenuItem(strings().chatInputUnblock, handler: {
                        arguments.removePeer(peer.id)
                    }, itemImage: MenuAnimation.menu_unblock.value)])
                } else {
                    return .single([])
                }
                
            })
        case let .empty(progress):
            return SearchEmptyRowItem(initialSize, stableId: stableId, isLoading: progress, text: strings().blockedPeersEmptyDescrpition, viewType: .singleItem)
        case .section:
            return GeneralRowItem(initialSize, height: 20, stableId: stableId, viewType: .separator)
        }
    }
}

private func blockedPeersControllerEntries(state: PeerListEditingState, blockedState: BlockedPeersContextState) -> [BlockedPeerEntry] {
    
    var entries: [BlockedPeerEntry] = []
    
    var index: Int32 = 0
    var sectionId: Int32 = 0
    if !blockedState.peers.isEmpty {
        entries.append(.section(sectionId))
        sectionId += 1
    }
    let list = blockedState.peers.filter { $0.peer?.isDeleted == false }
    for rendered in list {
        if let peer = rendered.peer {
            var deleting:ShortPeerDeleting? = nil
            if state.editing {
                deleting = ShortPeerDeleting(editable: true)
            }

            entries.append(.peerItem(sectionId, index, peer, deleting, state.removingPeerId != peer.id, bestGeneralViewType(list, for: rendered)))
            index += 1
        }
    }
    
    if blockedState.peers.isEmpty {
        entries.append(.empty(blockedState.isLoadingMore))
    } else {
        entries.append(.section(sectionId))
        sectionId += 1
    }
    
    return entries
}

fileprivate func prepareTransition(left:[AppearanceWrapperEntry<BlockedPeerEntry>], right: [AppearanceWrapperEntry<BlockedPeerEntry>], initialSize:NSSize, arguments:BlockedPeerControllerArguments) -> TableUpdateTransition {
    
    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return entry.entry.item(arguments, initialSize: initialSize)
    }
    
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: true, grouping: false)
}


open class BlockedPeersViewController<Context: AccountContextProtocol>: EditableViewController<TableView, Context> {
    
    
    private let statePromise = ValuePromise(PeerListEditingState(), ignoreRepeated: true)
    private let stateValue = Atomic(value: PeerListEditingState())
    private let removePeerDisposable:MetaDisposable = MetaDisposable()
    
    private let disposable:MetaDisposable = MetaDisposable()
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        genericView.contentInsets = NavigationBarView.contentTopInset

        genericView.getBackgroundColor = {
            theme.colors.listBackground
        }
        
        let context = self.context
        
        let updateState: ((PeerListEditingState) -> PeerListEditingState) -> Void = { [weak self] f in
            if let strongSelf = self {
                strongSelf.statePromise.set(strongSelf.stateValue.modify { f($0) })
            }
        }
        
        let arguments = BlockedPeerControllerArguments(context: context, removePeer: { [weak self] memberId in
            updateState {
                return $0.withUpdatedRemovingPeerId(memberId)
            }
            self?.removePeerDisposable.set((context.blockedPeersContext.remove(peerId: memberId) |> deliverOnMainQueue).start(error: { error in
                switch error {
                case .generic:
                    alert(for: context.window, info: strings().unknownError)
                }
                updateState {
                    return $0.withUpdatedRemovingPeerId(nil)
                }
            }, completed: {
                updateState {
                    return $0.withUpdatedRemovingPeerId(nil)
                }
            }))
        }, openPeer: { [weak self] peerId in
            guard let `self` = self else {return}
            if let navigation = self.navigationController {
                BlockedPeersHooks.shared.openPeerInfo(navigation, self.context, peerId)
            }
        })
        
        
        
        let initialSize = atomicSize
        let previousEntries:Atomic<[AppearanceWrapperEntry<BlockedPeerEntry>]> = Atomic(value: [])
        
        
        let signal = combineLatest(statePromise.get(), context.blockedPeersContext.state, appearanceSignal)
            |> deliverOnMainQueue
            |> map { state, blockedState, appearance -> TableUpdateTransition in
                let entries = blockedPeersControllerEntries(state: state, blockedState: blockedState).map{AppearanceWrapperEntry(entry: $0, appearance: appearance)}
                return prepareTransition(left: previousEntries.swap(entries), right: entries, initialSize: initialSize.modify{$0}, arguments: arguments)
            }
        
        disposable.set((signal |> deliverOnMainQueue).start(next: { [weak self] transition in
            if let strongSelf = self {
                strongSelf.genericView.merge(with: transition)
                strongSelf.readyOnce()
                strongSelf.rightBarView.isHidden = strongSelf.genericView.item(at: 0) is SearchEmptyRowItem
            }
        }))
        
        genericView.setScrollHandler { position in
            switch position.direction {
            case .bottom:
                context.blockedPeersContext.loadMore()
            default:
                break
            }
        }
    }
    
    deinit {
        disposable.dispose()
        removePeerDisposable.dispose()
    }
    
    open override func update(with state: ViewControllerState) {
        super.update(with: state)
        self.statePromise.set(stateValue.modify({$0.withUpdatedEditing(state == .Edit)}))
    }
    
}

