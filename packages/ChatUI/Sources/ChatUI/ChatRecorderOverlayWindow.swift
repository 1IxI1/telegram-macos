import Cocoa
import Foundation
import TGUIKit
import SwiftSignalKit
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramMedia
import ObjcUtils
import TGVideoCameraMovie
import AVFoundation

public enum ChatRecordingOverlayState: Equatable {
    case voice
    case video
    case fixed
}

final class ChatRecorderOverlayWindow: Window {
    private static let margin: CGFloat = 120

    private weak var parentHost: Window?

    init(parent: Window) {
        self.parentHost = parent
        super.init(contentRect: parent.frame.insetBy(dx: -ChatRecorderOverlayWindow.margin, dy: -ChatRecorderOverlayWindow.margin), styleMask: [.borderless], backing: .buffered, defer: false)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isReleasedWhenClosed = false
        self.animationBehavior = .none
        self.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        self.level = parent.level
        self.appearance = parent.appearance
        self._canBecomeKey = false
        self._canBecomeMain = false
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.masksToBounds = false
    }

    func attach() {
        guard let parent = self.parentHost else {
            return
        }
        self.updateFrame()
        if self.parent !== parent {
            parent.addChildWindow(self, ordered: .above)
        }
    }

    func detach() {
        self.parentHost?.removeChildWindow(self)
        self.orderOut(nil)
    }

    func updateFrame() {
        guard let parent = self.parentHost else {
            return
        }
        let frame = parent.frame.insetBy(dx: -ChatRecorderOverlayWindow.margin, dy: -ChatRecorderOverlayWindow.margin)
        if self.frame != frame {
            self.setFrame(frame, display: false)
        }
    }

    func convert(_ point: NSPoint, fromWindow window: NSWindow) -> NSPoint {
        guard let contentView = self.contentView else {
            return point
        }
        return contentView.convert(self.convertPoint(fromScreen: window.convertPoint(toScreen: point)), from: nil)
    }

    func convert(_ point: NSPoint, from view: NSView) -> NSPoint {
        guard let window = view.window else {
            return point
        }
        return self.convert(view.convert(point, to: nil), fromWindow: window)
    }
}

public final class ChatRecorderLockControl : View {
    private let idleView: LottiePlayerView = LottiePlayerView()
    private let lockingView: LottiePlayerView = LottiePlayerView()

    private var glassEffect: LiquidGlassView?
    private let glassWidth: CGFloat = 40

    private var lockData: Data?
    private var idleData: Data?
    private let animSize: NSSize

    public required init(frame frameRect: NSRect) {
        self.animSize = NSMakeSize(frameRect.width, frameRect.width)
        super.init(frame: frameRect)
        layer?.masksToBounds = false

        let glass = LiquidGlassView(frame: NSZeroRect, cornerRadius: glassWidth / 2, hasShadow: true, hasBorder: true)
        glassEffect = glass
        addSubview(glass)

        addSubview(idleView)
        addSubview(lockingView)
        lockingView.isHidden = true

        if let path = Bundle.main.path(forResource: "LockWait", ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            self.idleData = data
        }
        if let path = Bundle.main.path(forResource: "Lock", ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            self.lockData = data
        }

        updateLocalizationAndTheme(theme: theme)
        startIdle()
    }

    private func lottieColors() -> [LottieColor] {
        let color = theme.colors.text
        return [LottieColor(keyPath: "", color: color)]
    }

    private func startIdle() {
        guard let data = idleData else { return }
        let animation = LottieAnimation(compressed: data, key: .init(key: .bundle("LockWait"), size: animSize), cachePurpose: .none, playPolicy: .loop, maximumFps: 60, colors: lottieColors(), runOnQueue: .mainQueue())
        idleView.set(animation)
    }

    public func updateLockness(_ lockness: CGFloat) {
        currentLockness = lockness
        updateLayout(size: frame.size, transition: .immediate)
        if lockness > 0 {
            idleView.isHidden = true
            lockingView.isHidden = false
            if let data = lockData {
                let totalFrames: Int32 = 30
                let targetFrame = max(1, min(Int32(lockness * CGFloat(totalFrames)), totalFrames - 1))
                let animation = LottieAnimation(compressed: data, key: .init(key: .bundle("Lock_\(targetFrame)"), size: animSize), cachePurpose: .none, playPolicy: .loopAt(firstStart: targetFrame, range: targetFrame...targetFrame), maximumFps: 60, colors: lottieColors(), runOnQueue: .mainQueue())
                lockingView.set(animation)
            }
        } else {
            idleView.isHidden = false
            lockingView.isHidden = true
        }
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        backgroundColor = .clear
        idleView.setColors(lottieColors())
        lockingView.setColors(lottieColors())
    }

    public override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    private var currentLockness: CGFloat = 0

    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        if let glass = glassEffect {
            let glassX = (size.width - glassWidth) / 2
            let glassFrame = NSMakeRect(glassX, 0, glassWidth, size.height)
            transition.updateFrame(view: glass, frame: glassFrame)
            glass.updateLayout(size: glassFrame.size, transition: transition)
            glass.cornerRadius = min(glassWidth, size.height) / 2
        }
        let animX = (size.width - animSize.width) / 2
        let baseY = (min(size.height, glassWidth) - animSize.height) / 2
        let offset = 5 * (1.0 - currentLockness)
        let animY = baseY + offset
        transition.updateFrame(view: idleView, frame: NSMakeRect(animX, animY, animSize.width, animSize.height))
        transition.updateFrame(view: lockingView, frame: NSMakeRect(animX, animY, animSize.width, animSize.height))
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


public class ChatRecorderRoundButton : ImageButton {
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autohighlight = false
        scaleOnClick = true
        setGlassEffect(size: NSMakeSize(40, 40))
        updateLocalizationAndTheme(theme: theme)
    }

    public func icon(_ theme: TelegramPresentationTheme) -> CGImage? {
        return nil
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        backgroundColor = .clear
        if let icon = icon(theme) {
            set(image: icon, for: .Normal)
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public final class ChatRecorderSingleTimeControl : ChatRecorderRoundButton {
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        set(handler: { control in
            control.isSelected = !control.isSelected
        }, for: .Click)
    }

    public override var isSelected: Bool {
        didSet {
            updateLocalizationAndTheme(theme: theme)
        }
    }

    public override func icon(_ theme: TelegramPresentationTheme) -> CGImage? {
        return NSImage(named: isSelected ? "Icon_OnceView_Filled" : "Icon_OnceView")!.precomposed(theme.colors.text)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public final class ChatRecorderPauseControl : ChatRecorderRoundButton {
    public enum Kind {
        case pause
        case recordMore
    }

    public var kind: Kind = .pause {
        didSet {
            if kind != oldValue {
                updateLocalizationAndTheme(theme: theme)
            }
        }
    }

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    private static let iconSize: NSSize = NSMakeSize(30, 30)

    public override func icon(_ theme: TelegramPresentationTheme) -> CGImage? {
        switch kind {
        case .pause:
            let color = theme.colors.text
            return generateImage(ChatRecorderPauseControl.iconSize, rotatedContext: { size, context in
                context.clear(size.bounds)
                context.setFillColor(color.cgColor)
                let barWidth: CGFloat = 4.5
                let barHeight: CGFloat = 14
                let barSpacing: CGFloat = 7.5
                let cornerRadius: CGFloat = 1.5
                let x = (size.width - barSpacing - barWidth) / 2
                let y = (size.height - barHeight) / 2
                context.addPath(CGPath(roundedRect: NSMakeRect(x, y, barWidth, barHeight), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
                context.addPath(CGPath(roundedRect: NSMakeRect(x + barSpacing, y, barWidth, barHeight), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
                context.fillPath()
            })!
        case .recordMore:
            return FastSettings.recordingState == .voice ? theme.icons.chat_input_record_voice : theme.icons.chat_input_record_video
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public class ChatRecorderOverlayView : Control {
    private let stateView: ImageView = ImageView()
    private var isPaused: Bool = false
    let blobView: ChatRecordingBlobView
    private let recordingCentreDiameter: CGFloat
    private let pausedCentreDiameter: CGFloat = 40

    public required init(frame frameRect: NSRect) {
        recordingCentreDiameter = frameRect.width - 40
        let side = ChatRecordingBlobAppearance.side(centreDiameter: recordingCentreDiameter)
        blobView = ChatRecordingBlobView(frame: NSMakeRect(0, 0, side, side))

        super.init(frame: frameRect)
        layer?.masksToBounds = false
        backgroundColor = .clear

        addSubview(blobView)
        blobView.center()
        blobView.isDarkAppearance = theme.colors.isDark
        blobView.setColor(theme.colors.accent, animated: false)
        addSubview(stateView)

        blobView.startAnimating()
    }

    var isFlat: Bool {
        get {
            return blobView.isFlat
        }
        set {
            blobView.isFlat = newValue
        }
    }

    public func updateState(_ overlayState: ChatRecordingOverlayState) {
        switch overlayState {
        case .voice:
            stateView.image = theme.icons.chatOverlayVoiceRecording
        case .video:
            stateView.image = theme.icons.chatOverlayVideoRecording
        case .fixed:
            stateView.image = theme.icons.send_message_large
        }
        stateView.sizeToFit()
        stateView.center()

        updateInside()
    }

    func updateLevel(_ level: CGFloat) {
        blobView.updateLevel(level)
    }

    public func updatePaused(_ paused: Bool) {
        guard paused != isPaused else {
            return
        }
        isPaused = paused
        isEventLess = paused
        let side = ChatRecordingBlobAppearance.side(centreDiameter: paused ? pausedCentreDiameter : recordingCentreDiameter)
        blobView.setFrameSize(NSMakeSize(side, side))
        blobView.center()
        if paused {
            blobView.stopAnimating()
        } else {
            blobView.startAnimating()
        }
        updateInside()
    }

    public func updateInside() {
        let color = (isPaused || mouseInside()) ? theme.colors.accent : theme.colors.redUI
        blobView.setColor(color, animated: true)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
