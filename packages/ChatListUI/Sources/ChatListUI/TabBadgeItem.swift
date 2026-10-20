import Cocoa
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import AvatarUI
import TelegramMedia
import LocalAnimations


private final class AvatarTabContainer : View {
    private let avatar = AvatarControl(font: .avatar(12))
    private var selected: Bool = false
    private let circle: View = View()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        avatar.setFrameSize(frameRect.size)
        avatar.userInteractionEnabled = false
        circle.setFrameSize(frameRect.size)
        circle.layer?.cornerRadius = frameRect.height / 2
        circle.layer?.borderWidth = 1.33
        circle.layer?.borderColor = theme.colors.accentIcon.cgColor
        addSubview(circle)
        addSubview(avatar)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    func setPeer(account: Account, peer: Peer?) {
        avatar.setPeer(account: account, peer: peer)
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        circle.layer?.borderColor = theme.colors.accentIcon.cgColor
    }
    
    
    override func layout() {
        super.layout()
        avatar.center()
    }
    
    func setSelected(_ selected: Bool, animated: Bool) {
        self.selected = selected
        
        circle.change(opacity: selected ? 1 : 0, animated: animated, duration: 0.4, timingFunction: .spring)
        
        avatar.setFrameSize(frame.size)

        let from: CGFloat = selected ? 1 : 24 / frame.height
        let to: CGFloat = selected ? 24 / frame.height : 1
        avatar.layer?.animateScaleSpring(from: from, to: to, duration: 0.3, removeOnCompletion: false, bounce: false, completion: { completed in
            
        })
        
        if animated {
            if selected {
                circle.layer?.animateScaleSpring(from: 0.5, to: 1.0, duration: 0.3, bounce: false)
            } else {
                circle.layer?.animateScaleSpring(from: 1.0, to: 0.5, duration: 0.3, removeOnCompletion: false, bounce: false)
            }
        }

        needsLayout = true
    }

}


private final class TabAnimatedIconView : LottiePlayerView {
    private let sticker: LocalAnimatedSticker
    private var selected: Bool = false

    init(sticker: LocalAnimatedSticker) {
        self.sticker = sticker
        super.init(frame: NSMakeRect(0, 0, 48, 48))
        isEventLess = true
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init() {
        fatalError("init() has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var colors: [LottieColor] {
        return [.init(keyPath: "", color: selected ? theme.colors.accentIcon : theme.colors.grayIcon)]
    }

    func setSelected(_ selected: Bool, animated: Bool) {
        self.selected = selected
        apply(playing: animated && selected)
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        if self.animation?.colors != colors {
            apply(playing: false)
        }
    }

    private func apply(playing: Bool) {
        guard let data = sticker.data else {
            return
        }
        let policy: LottiePlayPolicy = playing ? .toEnd(from: 0) : .toEnd(from: .max)
        let animation = LottieAnimation(compressed: data, key: .init(key: .bundle(sticker.rawValue), size: frame.size), cachePurpose: .none, playPolicy: policy, colors: colors, runOnQueue: .mainQueue())
        set(animation, saveContext: true)
    }
}

public class TabAnimatedItem: TabItem {
    public let sticker: LocalAnimatedSticker
    public init(_ sticker: LocalAnimatedSticker, image: CGImage, selectedImage: CGImage, controller: ViewController, subNode: Node? = nil, longHoverHandler: ((Control)->Void)? = nil) {
        self.sticker = sticker
        super.init(image: image, selectedImage: selectedImage, controller: controller, subNode: subNode, longHoverHandler: longHoverHandler)
    }

    public override func withUpdatedImages(_ image: CGImage, _ selectedImage: CGImage) -> TabItem {
        return TabAnimatedItem(sticker, image: image, selectedImage: selectedImage, controller: self.controller, subNode: self.subNode, longHoverHandler: self.longHoverHandler)
    }

    public override func makeView() -> NSView {
        return TabAnimatedIconView(sticker: sticker)
    }

    public override func setSelected(_ selected: Bool, for view: NSView, animated: Bool) {
        if let view = view as? TabAnimatedIconView {
            view.setSelected(selected, animated: animated)
        } else {
            super.setSelected(selected, for: view, animated: animated)
        }
    }
}

public class TabBadgeItem: TabAnimatedItem {
    private let context:any AccountContextProtocol
    public init(_ context: any AccountContextProtocol, controller:ViewController, image: CGImage, selectedImage: CGImage, longHoverHandler:((Control)->Void)? = nil) {
        self.context = context
        super.init(.tab_chats, image: image, selectedImage: selectedImage, controller: controller, subNode:ChatListUIHooks.shared.makeTabBadgeNode(context), longHoverHandler: longHoverHandler)
    }
    public override func withUpdatedImages(_ image: CGImage, _ selectedImage: CGImage) -> TabItem {
        return TabBadgeItem(context, controller: self.controller, image: image, selectedImage: selectedImage, longHoverHandler: self.longHoverHandler)
    }
}
public class TabAllBadgeItem: TabAnimatedItem {
    private let context:any AccountContextProtocol
    private let disposable = MetaDisposable()
    private var peer: Peer?
    public init(_ context: any AccountContextProtocol, image: CGImage, selectedImage: CGImage, controller:ViewController, subNode:Node? = nil, longHoverHandler:((Control)->Void)? = nil) {
        self.context = context
        super.init(.tab_settings, image: image, selectedImage: selectedImage, controller: controller, subNode:ChatListUIHooks.shared.makeTabAllBadgeNode(context), longHoverHandler: longHoverHandler)
    }
    deinit {
        disposable.dispose()
    }
    
    public override func withUpdatedImages(_ image: CGImage, _ selectedImage: CGImage) -> TabItem {
        return TabAllBadgeItem(context, image: image, selectedImage: selectedImage, controller: self.controller, subNode: self.subNode, longHoverHandler: self.longHoverHandler)
    }
    
    public override func makeView() -> NSView {
        let context = self.context
        
        let semaphore = DispatchSemaphore(value: 0)
        var isMultiple = true
        _ = (context.sharedContext.activeAccounts |> take(1)).start(next: { accounts in
            isMultiple = accounts.accounts.count > 1
            semaphore.signal()
        })

        semaphore.wait()
        
        if !isMultiple {
            return super.makeView()
        }
        
        let view = AvatarTabContainer(frame: NSMakeRect(0, 0, 30, 30))
        /*
         |> distinctUntilChanged(isEqual: { lhs, rhs -> Bool in
         return lhs?.smallProfileImage != rhs?.smallProfileImage
         })
 */
        disposable.set((context.account.postbox.peerView(id: context.account.peerId) |> map { $0.peers[$0.peerId] } |> deliverOnMainQueue).start(next: { [weak view] peer in
            view?.setPeer(account: context.account, peer: peer)
        }))
        
        return view
    }
    
    public override func setSelected(_ selected: Bool, for view: NSView, animated: Bool) {
        (view as? AvatarTabContainer)?.setSelected(selected, animated: animated)
        super.setSelected(selected, for: view, animated: animated)
    }
    
}
