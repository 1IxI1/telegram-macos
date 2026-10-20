import Cocoa
import TGUIKit
import CoreText
import SwiftSignalKit
import TelegramMedia
import TelegramTheme
import TelegramContext
import GeneralRows
import SceneEffects
import Metal
import MetalEngine
import Localization

private let walletCardBaseColor = NSColor(rgb: 0x0088ff)
private let walletCardSecondaryColor = NSColor(rgb: 0x6ddcff)
private let walletCardAddressColor = NSColor(rgb: 0x005dda)
let walletCardReferenceSize = NSMakeSize(370, 220)
let walletTransferCardReferenceSize = NSMakeSize(361, 220)
private let walletCardCollapsedScale: CGFloat = 0.19
private let walletCardCollapsedPitch: CGFloat = .pi / 3.0
private let walletCardDiamondBaseSpin: CGFloat = 2.0 * .pi / 26.0
private let walletCardMaxDiamondRoll: CGFloat = 0.30 * 0.18

struct WalletCardDiamondLayout {
    let gramIconFrame: NSRect
    let balanceOriginX: CGFloat
    let diamondFrame: NSRect
    let diamondWidth: CGFloat
    let leftInset: CGFloat

    init(scale: CGFloat, balanceScale: CGFloat = 1.0) {
        let contentScale = scale * balanceScale
        let mainCenterY = 94.0 * scale
        let gramIconSide = 30.0 * contentScale
        let rowOriginX = 20.0 * scale
        let diamondSide = 96.0 * contentScale
        self.gramIconFrame = NSMakeRect(rowOriginX - contentScale, mainCenterY - gramIconSide / 2 - 3.0 * contentScale, gramIconSide, gramIconSide)
        self.balanceOriginX = rowOriginX + gramIconSide + 3.25 * contentScale
        self.diamondFrame = NSMakeRect(self.gramIconFrame.midX - diamondSide / 2, self.gramIconFrame.midY - diamondSide / 2, diamondSide, diamondSide)
        self.diamondWidth = 26.0 * 1.09 * 0.8 * contentScale
        self.leftInset = self.gramIconFrame.midX - 14.0 * contentScale
    }

    static func tilt(pitch: CGFloat, roll: CGFloat, scrollCollapseFraction: CGFloat) -> (pitch: CGFloat, roll: CGFloat) {
        let followsCardTilt = scrollCollapseFraction == 0.0
        return (followsCardTilt ? pitch : 0.0, followsCardTilt ? roll : 0.0)
    }
}

struct WalletCardBalanceFit {
    let balanceScale: CGFloat
    let fiatScale: CGFloat

    init(width: CGFloat, scale: CGFloat, qrWidth: CGFloat, hasFractional: Bool, balanceTextWidth: CGFloat, fiatWidth: CGFloat) {
        let balanceRightEdge = width - qrWidth - 47.0 * scale - 10.0 * scale
        let balanceWidth = (33.25 + (hasFractional ? 1.0 : 0.0) + 5.0) * scale + balanceTextWidth
        self.balanceScale = min(1.0, max(0.0, balanceRightEdge - 20.0 * scale) / max(1.0, balanceWidth))
        self.fiatScale = min(1.0, max(0.0, balanceRightEdge - 24.0 * scale) / max(1.0, fiatWidth))
    }
}

struct WalletCardDiamondSway {
    private(set) var rate: CGFloat = 0.0
    private(set) var roll: CGFloat = 0.0
    private var previousRotation: (rotation: CGFloat, time: CFTimeInterval)?

    var isActive: Bool {
        return abs(rate) > walletCardDiamondBaseSpin * 1.5 || roll != 0.0
    }

    mutating func update(rotation: CGFloat?, at time: CFTimeInterval) {
        guard let rotation else {
            previousRotation = nil
            rate = 0.0
            return
        }
        if let previous = previousRotation, time > previous.time {
            let delta = atan2(sin(rotation - previous.rotation), cos(rotation - previous.rotation))
            let deltaTime = time - previous.time
            rate += (delta / deltaTime - rate) * min(1.0, deltaTime * 3.0)
        }
        previousRotation = (rotation, time)
    }

    mutating func step(deltaTime: CGFloat) {
        let extraSpin = rate - walletCardDiamondBaseSpin * (rate >= 0.0 ? 1.0 : -1.0)
        let rollTarget = max(-walletCardMaxDiamondRoll, min(walletCardMaxDiamondRoll, 0.006 * (abs(rate) > walletCardDiamondBaseSpin * 1.5 ? extraSpin : 0.0)))
        roll += (rollTarget - roll) * (1.0 - exp(-deltaTime * 2.5))
        if rollTarget == 0.0, abs(roll) < 1e-4 {
            roll = 0.0
        }
    }

    mutating func reset() {
        self = WalletCardDiamondSway()
    }
}
private let walletChatCardGramIconSide: CGFloat = 40
private let walletChatCardGramAnimationSide: CGFloat = 48
private let walletChatCardDiamondSide: CGFloat = 38
private let walletChatCardDiamondCanvas: CGFloat = 64

func walletGramIcon(_ side: CGFloat) -> CGImage? {
    guard let image = NSImage(named: "Wallet_CardGram") else {
        return nil
    }
    return image.precomposed(zoom: side / image.size.width)
}

private func walletCardTextBaseline(_ view: TextView) -> CGFloat {
    return view.textLayout?.lines.first?.frame.minY ?? 0
}

private func walletCardScaledFrame(_ view: NSView, _ scale: CGFloat) -> NSRect {
    return NSRect(origin: view.frame.origin, size: NSMakeSize(view.frame.width * scale, view.frame.height * scale))
}

private func walletCardSmoothStep(_ value: CGFloat) -> CGFloat {
    let clamped = max(0.0, min(1.0, value))
    return clamped * clamped * (3.0 - 2.0 * clamped)
}

private let walletCardThickness: CGFloat = 9.0
let walletCardMaxHoverTilt: CGFloat = 6.5 * .pi / 180.0
private let walletCardSurfaceMaxYaw: CGFloat = 0.30

func walletCardSurfaceTilt(pitch: CGFloat, yaw: CGFloat, roll: CGFloat) -> CGPoint {
    let x = (yaw - roll) / walletCardMaxHoverTilt + roll / walletCardSurfaceMaxYaw
    let y = pitch / walletCardMaxHoverTilt
    return CGPoint(x: max(-1.0, min(1.0, x)), y: max(-1.0, min(1.0, y)))
}

func walletCardFitTransforms(face: CATransform3D, edgeShift: CGPoint, size: CGSize) -> (face: CATransform3D, edge: CATransform3D) {
    let anchor = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
    var reachX: CGFloat = 0.0
    for corner in [CGPoint(x: 0.0, y: 0.0), CGPoint(x: size.width, y: 0.0), CGPoint(x: 0.0, y: size.height), CGPoint(x: size.width, y: size.height)] {
        let w = corner.x * face.m14 + corner.y * face.m24 + face.m44
        let safeW = abs(w) < 0.0001 ? 0.0001 : w
        let x = (corner.x * face.m11 + corner.y * face.m21 + face.m41) / safeW - anchor.x
        reachX = max(reachX, max(abs(x), abs(x + edgeShift.x)))
    }
    let fitScale = reachX > anchor.x ? anchor.x / reachX : 1.0
    var fit = CATransform3DMakeTranslation(-anchor.x, -anchor.y, 0.0)
    fit = CATransform3DConcat(fit, CATransform3DMakeScale(fitScale, fitScale, 1.0))
    fit = CATransform3DConcat(fit, CATransform3DMakeTranslation(anchor.x, anchor.y, 0.0))
    let fitted = CATransform3DConcat(face, fit)
    return (fitted, CATransform3DConcat(fitted, CATransform3DMakeTranslation(edgeShift.x * fitScale, edgeShift.y * fitScale, 0.0)))
}

func walletCardEdgeShift(pitch: CGFloat, yaw: CGFloat, width: CGFloat) -> CGPoint {
    let depth = -walletCardThickness * width / walletCardReferenceSize.width
    var rotation = CATransform3DRotate(CATransform3DIdentity, pitch, 1.0, 0.0, 0.0)
    rotation = CATransform3DRotate(rotation, yaw, 0.0, 1.0, 0.0)
    return CGPoint(x: depth * rotation.m31, y: depth * rotation.m32)
}

private func walletCardMaterialColor(_ linear: [CGFloat]) -> [CGFloat] {
    let encoded = linear.map { value -> CGFloat in
        let value = max(value, 0.0)
        return value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1.0 / 2.4) - 0.055
    }
    let luminance = encoded[0] * 0.2126 + encoded[1] * 0.7152 + encoded[2] * 0.0722
    return encoded.map { max(0.0, min(1.0, luminance + ($0 - luminance) * 1.6)) }
}

private func walletCardEdgeColor(diffuse: CGFloat) -> CGColor {
    let shade = 0.62 + 0.62 * diffuse
    let material = walletCardMaterialColor([0.014 * shade, 0.085 * shade, 0.40 * shade])
    let tint: [CGFloat] = [1.05933, 0.912212, 0.968627]
    let channels = (0 ..< 3).map { max(0.0, min(1.0, material[$0] * tint[$0])) }
    return NSColor(srgbRed: channels[0], green: channels[1], blue: channels[2], alpha: 1.0).cgColor
}

private let walletCardBevelSteps = 256

private let walletCardBevelLevels: [UInt8] = {
    let baseColor = walletCardBaseColor.usingColorSpace(.sRGB) ?? walletCardBaseColor
    let base = [baseColor.redComponent, baseColor.greenComponent, baseColor.blueComponent].map { value -> CGFloat in
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    let baseMaterial = walletCardMaterialColor(base)
    var levels = [UInt8](repeating: 0, count: (walletCardBevelSteps + 1) * 3)
    for step in 0 ... walletCardBevelSteps {
        let weight = walletCardBevelWeight(lightDot: CGFloat(step) / CGFloat(walletCardBevelSteps))
        let lit = walletCardMaterialColor([base[0] + 0.10 * weight, base[1] + 0.36 * weight, base[2] + 0.85 * weight])
        for channel in 0 ..< 3 {
            levels[step * 3 + channel] = UInt8(max(0.0, min(255.0, ((lit[channel] - baseMaterial[channel]) * 0.725 * 255.0).rounded())))
        }
    }
    return levels
}()

func walletCardBevelLight(surface: CGPoint) -> CGPoint {
    let x = -0.45 - 0.9 * surface.x
    let y = -0.9 + 0.7 * surface.y
    let length = hypot(x, y)
    return CGPoint(x: x / length, y: y / length)
}

func walletCardBevelWeight(lightDot: CGFloat) -> CGFloat {
    return 0.03 + 0.26 * max(lightDot, 0.0)
}

private func walletCardBevelImage(size: NSSize, cornerRadius: CGFloat, surface: CGPoint) -> CGImage? {
    let width = max(2, Int(ceil(size.width / 4.0)))
    let height = max(2, Int(ceil(size.height / 4.0)))
    let light = walletCardBevelLight(surface: surface)
    let halfSize = CGSize(width: size.width / 2.0, height: size.height / 2.0)
    let radius = min(cornerRadius, min(halfSize.width, halfSize.height))
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    for py in 0 ..< height {
        for px in 0 ..< width {
            let point = CGPoint(x: (CGFloat(px) + 0.5) * size.width / CGFloat(width) - halfSize.width, y: (CGFloat(py) + 0.5) * size.height / CGFloat(height) - halfSize.height)
            let normal = walletCardRoundRectNormal(point, halfSize, radius)
            let lightDot = max(0.0, min(1.0, normal.x * light.x + normal.y * light.y))
            let level = Int((lightDot * CGFloat(walletCardBevelSteps)).rounded()) * 3
            let offset = py * bytesPerRow + px * 4
            pixels[offset] = walletCardBevelLevels[level]
            pixels[offset + 1] = walletCardBevelLevels[level + 1]
            pixels[offset + 2] = walletCardBevelLevels[level + 2]
            pixels[offset + 3] = 255
        }
    }
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            return nil
        }
        return context.makeImage()
    }
}

@available(macOS 10.15, *)
func walletCardRoundedFont(_ size: CGFloat, monospacedDigits: Bool = true) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .semibold)
    var descriptor = base.fontDescriptor
    if let rounded = descriptor.withDesign(.rounded) {
        descriptor = rounded
    }
    if monospacedDigits {
        descriptor = descriptor.addingAttributes([.featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType, NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]]])
    }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

func splitWalletBalanceText(_ balance: Int64) -> (integral: String, fractional: String) {
    let formatted = formatTonAmountText(balance, maxDecimalPositions: 2)
    let decimalSeparator = Locale.current.decimalSeparator ?? "."
    if balance == 0 {
        return (formatted, "")
    }
    if let separatorRange = formatted.range(of: decimalSeparator) {
        return (String(formatted[..<separatorRange.lowerBound]), String(formatted[separatorRange.lowerBound...]))
    }
    return (formatted, "")
}

private func splitWalletTransferAmountText(amount: Int64, amountText: String?) -> (integral: String, fractional: String, isText: Bool) {
    let formatted = amountText ?? formatTonAmountText(amount, maxDecimalPositions: 9)
    let decimalSeparator = walletDecimalSeparator
    let isText = amountText?.unicodeScalars.contains(where: CharacterSet.letters.contains) == true
    if isText || (amount == 0 && amountText == nil) {
        return (formatted, "", isText)
    }
    if let separatorRange = formatted.range(of: decimalSeparator) {
        var digits = String(formatted[separatorRange.upperBound...])
        while digits.count < 2 {
            digits.append("0")
        }
        return (String(formatted[..<separatorRange.lowerBound]), decimalSeparator + digits, false)
    }
    return (formatted, decimalSeparator + "00", false)
}

func walletTransferCardRecipientText(_ address: String) -> String {
    let groups = walletAddressGroups(address)
    let splitIndex = min(6, groups.count)
    let firstLine = groups[..<splitIndex].joined(separator: " ")
    let secondLine = groups.dropFirst(splitIndex).joined(separator: " ")
    return secondLine.isEmpty ? firstLine : firstLine + "\n" + secondLine
}

private func walletCardAddressLines(_ address: String) -> [String] {
    let groups = walletAddressGroups(address)
    let splitIndex = min(6, groups.count)
    let firstLine = groups[..<splitIndex].joined(separator: " ")
    let secondLine = groups.dropFirst(splitIndex).joined(separator: " ")
    var lines: [String] = []
    if !firstLine.isEmpty {
        lines.append(firstLine.uppercased())
    }
    if !secondLine.isEmpty {
        lines.append(secondLine.uppercased())
    }
    return lines
}

private func walletCardAddressImage(_ address: String, scale: CGFloat) -> (CGImage, NSSize)? {
    return walletCardAddressImage(lines: walletCardAddressLines(address).map { line in line.map { (character: $0, isSettled: true) } }, scale: scale)
}

private func walletCardAddressImage(lines: [[(character: Character, isSettled: Bool)]], scale: CGFloat) -> (CGImage, NSSize)? {
    if lines.isEmpty {
        return nil
    }

    let font: NSFont = .normalMonospaced(11.0 * scale)

    func makeNode(_ line: [(character: Character, isSettled: Bool)], _ color: NSColor) -> (TextNodeLayout, TextNode) {
        let text = NSMutableAttributedString()
        for (character, isSettled) in line {
            text.append(.initialize(string: String(character), color: isSettled ? color : color.withAlphaComponent(color.alphaComponent * 0.35), font: font))
        }
        return TextNode.layoutText(text, nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .left)
    }

    let mainNodes = lines.map { makeNode($0, walletCardAddressColor) }
    let outlineNodes = lines.map { makeNode($0, NSColor.white.withAlphaComponent(0.1)) }

    let lineSpacing: CGFloat = -0.05 * scale
    let lineHeight = ceil(font.ascender)
    var textSize = NSZeroSize
    for node in mainNodes {
        textSize.width = max(textSize.width, node.0.size.width)
    }
    textSize.height = lineHeight * CGFloat(mainNodes.count) + CGFloat(mainNodes.count - 1) * lineSpacing

    let horizontalSize = NSMakeSize(textSize.width + 1.0, textSize.height)

    guard let horizontal = generateImage(horizontalSize, rotatedContext: { size, ctx in
        ctx.clear(size.bounds)
        var y: CGFloat = 0
        for node in outlineNodes {
            node.1.draw(NSMakeRect(1, y, node.0.size.width, node.0.size.height), in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
            y += lineHeight + lineSpacing
        }
        y = 0
        for node in mainNodes {
            node.1.draw(NSMakeRect(0, y, node.0.size.width, node.0.size.height), in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
            y += lineHeight + lineSpacing
        }
    }) else {
        return nil
    }

    let verticalSize = NSMakeSize(horizontalSize.height, horizontalSize.width)
    guard let vertical = generateImage(verticalSize, rotatedContext: { size, ctx in
        ctx.clear(size.bounds)
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        ctx.rotate(by: .pi / 2)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(horizontal, in: NSMakeRect(-horizontalSize.width / 2, -horizontalSize.height / 2, horizontalSize.width, horizontalSize.height))
    }) else {
        return nil
    }

    return (vertical, verticalSize)
}

@available(macOS 10.15, *)
public final class WalletCardView: View {
    private let edgeView = View()
    private let edgeGradientLayer = CAGradientLayer()
    private let faceView = View()
    private let effectsLayer = SimpleLayer()
    private let effects = WalletCardEffectsLayers()
    private let bevelLayer = SimpleLayer()
    private let bevelMaskLayer = SimpleLayer()
    private var bevelImageKey: String?
    private var bevelRenderedSurface: CGPoint?
    private let gramIconView = ImageView()
    #if arch(arm64)
    private let gramDiamondView = InteractiveDiamondView(frame: NSZeroRect)
    #endif
    private let integralView = TextView()
    private let fractionalView = TextView()
    private let currencyView = TextView()
    private let fiatView = TextView()
    private let nameView = TextView()
    private let addressView = ImageView()
    private let qrButton = Control()
    private let qrIconView = ImageView()
    private let recipientView = TextView()
    private let infoButton = Control()
    private let infoIconView = ImageView()

    public var gramIconFrame: NSRect {
        return convert(gramIconView.bounds, from: gramIconView)
    }

    public var receiveAction: (() -> Void)?
    var transferInfoAction: (() -> Void)?

    private var isTransfer = false
    private var currencyText: String = "GRAM"
    private var recipientText: String = ""
    private var integralText: String = ""
    private var fractionalText: String = ""
    private var fiatText: String?
    private var nameText: String = ""
    private var nameLayout: TextViewLayout?
    private var appliedTextScale: CGFloat?
    private var balanceScale: CGFloat = 1.0
    private var fiatScale: CGFloat = 1.0
    private var integralFont: NSFont = .systemFont(ofSize: 22)
    private var fractionalFont: NSFont = .systemFont(ofSize: 18)
    private var currencyFont: NSFont = .systemFont(ofSize: 22)
    private var gramIconNativeSize: NSSize = .zero
    private var address: String = ""
    private var addressImageKey: String?
    private var addressImageSize: NSSize = .zero
    private var qrChipImageKey: String?
    private var qrChipRenderer: WalletCardQRChipRenderer?
    private var qrChipRendered: (surface: CGPoint, phase: CGFloat)?
    private var surfaceTilt: CGPoint = .zero
    private var surfaceTime: CGFloat = 0.0
    private var surfaceClock: ConstantDisplayLinkAnimator?

    private var tiltCurrent = WalletCardTilt()
    private var tiltTarget = WalletCardTilt()
    private var hoverLevel: CGFloat = 0.0
    private var isHovering = false
    private var tiltAnimator: ConstantDisplayLinkAnimator?
    private var cardTrackingArea: NSTrackingArea?
    private var scrollCollapseFraction: CGFloat = 0.0
    private var diamondSway = WalletCardDiamondSway()
    private var lastTiltTickTime: CFTimeInterval?
    private var introPending = false
    private var introStart: CFTimeInterval?
    private var introAnimator: ConstantDisplayLinkAnimator?
    private var digitRolls: [WalletDigitRoll] = []
    private var addressReveal: WalletAddressReveal?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        self.backgroundColor = .clear
        self.layer?.masksToBounds = false

        let edgeLight: CGFloat = 1.0 / hypot(0.35, 1.0)
        edgeGradientLayer.colors = [walletCardEdgeColor(diffuse: 0.5 + 0.5 * edgeLight), walletCardEdgeColor(diffuse: 0.5 - 0.5 * edgeLight)]
        edgeView.isEventLess = true
        edgeView.layer?.cornerCurve = .continuous
        edgeView.layer?.opacity = 0.0
        edgeView.layer?.addSublayer(edgeGradientLayer)
        addSubview(edgeView)

        faceView.backgroundColor = walletCardBaseColor
        faceView.layer?.cornerCurve = .continuous
        faceView.layer?.masksToBounds = true
        effectsLayer.backgroundColor = walletCardBaseColor.cgColor
        faceView.layer?.addSublayer(effectsLayer)
        addSubview(faceView)

        for textView in [integralView, fractionalView, currencyView, fiatView, nameView, recipientView] {
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            textView.disableBackgroundDrawing = true
            textView.isEventLess = true
            faceView.addSubview(textView)
        }

        gramIconView.isEventLess = true
        faceView.addSubview(gramIconView)
        #if arch(arm64)
        gramDiamondView.onExpansionChanged = { [weak self] _ in
            self?.updateDiamondRefraction()
        }
        gramDiamondView.onMotionUpdated = { [weak self] state in
            self?.updateDiamondRate(state)
        }
        faceView.addSubview(gramDiamondView)
        #endif

        addressView.isEventLess = true
        faceView.addSubview(addressView)

        qrButton.userInteractionEnabled = false
        qrButton.isEventLess = true
        qrButton.layer?.masksToBounds = false
        qrIconView.isEventLess = true
        qrIconView.contentGravity = .resizeAspect
        qrButton.addSubview(qrIconView)
        faceView.addSubview(qrButton)

        gramIconView.contentGravity = .resizeAspect
        gramIconView.image = NSImage(named: "Wallet_CardGram")?.precomposed()
        gramIconView.sizeToFit()
        gramIconNativeSize = gramIconView.frame.size

        qrButton.backgroundColor = .clear

        infoIconView.isEventLess = true
        infoIconView.contentGravity = .resizeAspect
        infoIconView.image = NSImage(named: "Wallet_CardInfo")?.precomposed()
        infoButton.backgroundColor = .clear
        infoButton.addSubview(infoIconView)
        infoButton.set(handler: { [weak self] _ in
            self?.transferInfoAction?()
        }, for: .Click)
        faceView.addSubview(infoButton)

        applyMode()
        effects.install(into: effectsLayer)

        bevelMaskLayer.borderWidth = 1.0
        bevelMaskLayer.borderColor = NSColor.white.cgColor
        bevelMaskLayer.cornerCurve = .continuous
        bevelLayer.contentsGravity = .resize
        bevelLayer.compositingFilter = "plusL"
        bevelLayer.mask = bevelMaskLayer
        effectsLayer.addSublayer(bevelLayer)
    }

    private func applyMode() {
        edgeView.isHidden = isTransfer
        bevelLayer.isHidden = isTransfer
        nameView.isHidden = isTransfer
        addressView.isHidden = isTransfer
        qrButton.isHidden = isTransfer
        recipientView.isHidden = !isTransfer
        infoButton.isHidden = !isTransfer
        #if arch(arm64)
        gramIconView.isHidden = !isTransfer
        gramDiamondView.isHidden = isTransfer
        #endif
        updateSurfaceClock()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var reduceMotion: Bool {
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cardTrackingArea {
            removeTrackingArea(cardTrackingArea)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        cardTrackingArea = area
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startTiltEngine()
        } else {
            tiltAnimator?.isPaused = true
        }
        updateSurfaceClock()
    }

    private func startTiltEngine() {
        guard !reduceMotion, scrollCollapseFraction < 1.0 else {
            diamondSway.reset()
            effects.setTwinkleEnabled(false)
            effects.apply(tilt: WalletCardTilt())
            tiltAnimator?.isPaused = true
            return
        }
        effects.setTwinkleEnabled(true)
        if tiltAnimator == nil {
            tiltAnimator = ConstantDisplayLinkAnimator(framesPerSecond: .max, update: { [weak self] duration in
                self?.tiltTick(duration)
            })
        }
        tiltAnimator?.isPaused = false
    }

    private func tiltTick(_ duration: CGFloat) {
        if !isHovering {
            tiltTarget = WalletCardTilt()
        }
        let chaseFactor = FrameStep.blend(isHovering ? 0.2 : 0.1, duration)
        let deltaX = tiltTarget.tx - tiltCurrent.tx
        let deltaY = tiltTarget.ty - tiltCurrent.ty
        tiltCurrent.tx += deltaX * chaseFactor
        tiltCurrent.ty += deltaY * chaseFactor
        let hoverTarget: CGFloat = isHovering ? 1.0 : 0.0
        let hoverDelta = hoverTarget - hoverLevel
        hoverLevel = abs(hoverDelta) < 5e-3 ? hoverTarget : hoverLevel + hoverDelta * FrameStep.blend(0.1, duration)
        let now = CACurrentMediaTime()
        let deltaTime = min(max(now - (lastTiltTickTime ?? now), 0.0), 1.0 / 30.0)
        lastTiltTickTime = now
        diamondSway.step(deltaTime: deltaTime)
        effects.apply(tilt: tiltCurrent)
        applyCardTilt()
        if abs(deltaX) < 5e-4, abs(deltaY) < 5e-4, hoverLevel == hoverTarget, !diamondSway.isActive {
            tiltAnimator?.isPaused = true
        }
    }

    private func updateDiamondRate(_ state: InteractiveDiamondView.MotionState?) {
        diamondSway.update(rotation: reduceMotion ? nil : state?.rotation, at: CACurrentMediaTime())
        if diamondSway.isActive, tiltAnimator?.isPaused != false, window != nil {
            startTiltEngine()
        }
    }

    private var cardTiltAngles: (x: CGFloat, y: CGFloat) {
        return (-tiltCurrent.ty * walletCardMaxHoverTilt * hoverLevel, tiltCurrent.tx * walletCardMaxHoverTilt * hoverLevel + diamondSway.roll)
    }

    private func applyCardTilt() {
        guard let faceLayer = faceView.layer else {
            return
        }
        let hoverStrength = hoverLevel
        let (angleX, angleY) = cardTiltAngles
        let width = frame.width
        let height = frame.height
        var transform = CATransform3DMakeTranslation(width / 2, height / 2, 0)
        transform.m34 = -max(hoverStrength, diamondSway.roll == 0.0 ? 0.0 : 1.0) / 800.0
        transform = CATransform3DRotate(transform, angleX, 1, 0, 0)
        transform = CATransform3DRotate(transform, angleY, 0, 1, 0)
        transform = CATransform3DTranslate(transform, -width / 2, -height / 2, 0)
        surfaceTilt = walletCardSurfaceTilt(pitch: angleX, yaw: angleY, roll: diamondSway.roll)
        let edgeShift = walletCardEdgeShift(pitch: angleX, yaw: angleY, width: width)
        var edgeTransform = CATransform3DConcat(transform, CATransform3DMakeTranslation(edgeShift.x, edgeShift.y, 0))
        if !isTransfer {
            (transform, edgeTransform) = walletCardFitTransforms(face: transform, edgeShift: edgeShift, size: NSMakeSize(width, height))
        }
        if !reduceMotion, scrollCollapseFraction > 0.0 {
            let fraction = scrollCollapseFraction
            let pitch = walletCardCollapsedPitch * fraction * (2.0 - fraction)
            let scale = 1.0 + (walletCardCollapsedScale - 1.0) * fraction
            var scroll = CATransform3DMakeTranslation(width / 2, height / 2, 0)
            scroll.m34 = -fraction / 650.0
            scroll = CATransform3DRotate(scroll, pitch, 1, 0, 0)
            scroll = CATransform3DScale(scroll, scale, scale, 1)
            scroll = CATransform3DTranslate(scroll, -width / 2, -height / 2, 0)
            transform = CATransform3DConcat(transform, scroll)
            edgeTransform = CATransform3DConcat(edgeTransform, scroll)
        }

        let parallaxX = tiltCurrent.tx * hoverStrength
        let parallaxY = tiltCurrent.ty * hoverStrength

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        faceLayer.transform = transform
        edgeView.layer?.transform = edgeTransform
        edgeView.layer?.opacity = hypot(edgeShift.x, edgeShift.y) * backingScaleFactor > 0.35 ? 1.0 : 0.0
        infoButton.layer?.transform = CATransform3DMakeTranslation(parallaxX * 6, parallaxY * 6, 0)
        recipientView.layer?.transform = CATransform3DMakeTranslation(parallaxX * 3, parallaxY * 3, 0)
        var balanceViews: [NSView] = [gramIconView]
        #if arch(arm64)
        balanceViews.append(gramDiamondView)
        #endif
        for view in balanceViews {
            view.layer?.transform = CATransform3DMakeTranslation(parallaxX * 4, parallaxY * 4, 0)
        }
        for view in [integralView, fractionalView, currencyView] {
            view.layer?.transform = CATransform3DScale(CATransform3DMakeTranslation(parallaxX * 4, parallaxY * 4, 0), balanceScale, balanceScale, 1.0)
        }
        fiatView.layer?.transform = CATransform3DScale(CATransform3DMakeTranslation(parallaxX * 3.5, parallaxY * 3.5, 0), fiatScale, fiatScale, 1.0)
        nameView.layer?.transform = CATransform3DMakeTranslation(parallaxX * 3, parallaxY * 3, 0)
        addressView.layer?.transform = CATransform3DMakeTranslation(parallaxX * 2, parallaxY * 2, 0)
        CATransaction.commit()
        #if arch(arm64)
        updateDiamondTilt()
        #endif
    }

    #if arch(arm64)
    private func updateDiamondRefraction() {
        let textViews = [integralView, fractionalView, currencyView].filter { !$0.isHidden && !$0.frame.isEmpty }
        guard !isTransfer, gramDiamondView.isExpanded, !textViews.isEmpty else {
            gramDiamondView.updateRefractionSource(nil)
            return
        }
        let scale = backingScaleFactor
        let sourceRect = textViews.reduce(NSRect.null) { $0.union(walletCardScaledFrame($1, balanceScale)) }.insetBy(dx: -2, dy: -2).integral
        let nodes = textViews.compactMap { view -> (TextNodeLayout, TextNode, NSRect)? in
            guard let attributedString = view.textLayout?.attributedString else {
                return nil
            }
            let node = TextNode.layoutText(attributedString, nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .left)
            return (node.0, node.1, view.frame)
        }
        guard let image = generateImage(sourceRect.size, scale: scale, rotatedContext: { size, ctx in
            ctx.clear(size.bounds)
            for (layout, node, frame) in nodes {
                ctx.saveGState()
                ctx.translateBy(x: frame.minX - sourceRect.minX, y: frame.minY - sourceRect.minY)
                ctx.scaleBy(x: self.balanceScale, y: self.balanceScale)
                node.draw(NSRect(origin: .zero, size: layout.size), in: ctx, backingScaleFactor: scale, backgroundColor: .clear)
                ctx.restoreGState()
            }
        }), let texture = walletDiamondRefractionTexture(image) else {
            gramDiamondView.updateRefractionSource(nil)
            return
        }
        let rect = sourceRect.offsetBy(dx: -gramDiamondView.frame.midX, dy: -gramDiamondView.frame.midY)
        gramDiamondView.updateRefractionSource(InteractiveDiamondView.RefractionSource(texture: texture, uv: SIMD4(0, 0, 1, 1), rect: rect, preservesColors: true))
    }

    private func updateDiamondTilt() {
        guard !isTransfer, frame.width > 0 else {
            return
        }
        let (angleX, angleY) = cardTiltAngles
        let tilt = WalletCardDiamondLayout.tilt(pitch: angleX, roll: angleY, scrollCollapseFraction: scrollCollapseFraction)
        let layout = WalletCardDiamondLayout(scale: frame.width / walletCardReferenceSize.width, balanceScale: balanceScale)
        gramDiamondView.updateWalletTilt(pitch: tilt.pitch, roll: tilt.roll, scale: 1.0, leftInset: layout.leftInset)
    }
    #endif

    private func updateTiltTarget(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let width = max(1.0, frame.width)
        let height = max(1.0, frame.height)
        tiltTarget.tx = max(-1.0, min(1.0, (point.x - width / 2) / (width / 2)))
        tiltTarget.ty = max(-1.0, min(1.0, (point.y - height / 2) / (height / 2)))
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovering = true
        updateTiltTarget(with: event)
        startTiltEngine()
    }

    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        isHovering = true
        updateTiltTarget(with: event)
        startTiltEngine()
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
        tiltTarget = WalletCardTilt()
        startTiltEngine()
    }

    private var isMouseDownInside = false

    public override func mouseDown(with event: NSEvent) {
        isMouseDownInside = receiveAction != nil
        if !isMouseDownInside {
            super.mouseDown(with: event)
        }
    }

    public override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isMouseDownInside, bounds.contains(point) {
            isMouseDownInside = false
            receiveAction?()
        } else {
            isMouseDownInside = false
            super.mouseUp(with: event)
        }
    }

    public func updateScrollCollapse(fraction: CGFloat) {
        let fraction = max(0.0, min(1.0, fraction))
        guard scrollCollapseFraction != fraction else {
            return
        }
        let wasCollapsed = scrollCollapseFraction >= 1.0
        scrollCollapseFraction = fraction
        #if arch(arm64)
        gramDiamondView.isRenderingEnabled = !isTransfer && fraction < 1.0
        updateDiamondInteraction()
        #endif
        applyScrollCollapseAppearance()
        applyCardTilt()
        updateSurfaceClock()
        if fraction >= 1.0 {
            tiltAnimator?.isPaused = true
            effects.setTwinkleEnabled(false)
        } else if wasCollapsed || tiltAnimator?.isPaused != false, window != nil {
            startTiltEngine()
        }
    }

    #if arch(arm64)
    private func updateDiamondInteraction() {
        let isInteractive = !isTransfer && scrollCollapseFraction == 0.0
        if gramDiamondView.isInteractionEnabled != isInteractive {
            gramDiamondView.isInteractionEnabled = isInteractive
        }
    }
    #endif

    private func applyScrollCollapseAppearance() {
        let detailsFraction = walletCardSmoothStep((scrollCollapseFraction - 0.3) / 0.3)
        let detailsAlpha = 1.0 - detailsFraction
        let currencyAlpha = 1.0 - walletCardSmoothStep(scrollCollapseFraction / 0.25)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for view in [nameView, addressView, qrButton, fiatView] {
            view.layer?.opacity = Float(detailsAlpha)
        }
        if detailsFraction > 0.0, let blurFilter = ee2_makeBlurFilter() {
            blurFilter.setValue(detailsFraction * 8.0 as NSNumber, forKey: "inputRadius")
            qrButton.layer?.filters = [blurFilter]
        } else {
            qrButton.layer?.filters = nil
        }
        currencyView.layer?.opacity = Float(currencyAlpha)
        CATransaction.commit()
    }

    public func update(balance: Int64, fiatText: String?, name: String, address: String, animated: Bool) {
        self.isTransfer = false
        self.currencyText = "GRAM"
        self.recipientText = ""
        applyMode()
        self.address = address

        let (integralText, fractionalText) = splitWalletBalanceText(balance)
        self.integralText = integralText
        self.fractionalText = fractionalText
        self.fiatText = fiatText
        self.nameText = name.uppercased()
        self.appliedTextScale = nil

        needsLayout = true
    }

    func updateTransfer(amount: Int64, amountText: String?, fiatText: String?, recipientText: String) {
        let (integralText, fractionalText, isText) = splitWalletTransferAmountText(amount: amount, amountText: amountText)
        self.isTransfer = true
        self.integralText = "−" + integralText
        self.fractionalText = fractionalText
        self.currencyText = isText ? "" : "GRAM"
        self.fiatText = fiatText
        self.recipientText = recipientText
        self.nameText = ""
        self.address = ""
        self.receiveAction = nil
        self.appliedTextScale = nil
        applyMode()

        needsLayout = true
    }

    private func applyBalanceTextLayouts(scale: CGFloat) {
        integralFont = walletCardRoundedFont(22.0 * scale)
        fractionalFont = walletCardRoundedFont(18.0 * scale)
        currencyFont = walletCardRoundedFont(22.0 * scale, monospacedDigits: false)

        let integralLayout = TextViewLayout(.initialize(string: integralText, color: .white, font: integralFont), maximumNumberOfLines: 1)
        integralLayout.measure(width: .greatestFiniteMagnitude)
        integralView.update(integralLayout)

        let fractionalLayout = TextViewLayout(.initialize(string: fractionalText, color: .white, font: fractionalFont), maximumNumberOfLines: 1)
        fractionalLayout.measure(width: .greatestFiniteMagnitude)
        fractionalView.update(fractionalLayout)

        let currencyLayout = TextViewLayout(.initialize(string: currencyText, color: walletCardSecondaryColor, font: currencyFont), maximumNumberOfLines: 1)
        currencyLayout.measure(width: .greatestFiniteMagnitude)
        currencyView.update(currencyLayout)
    }

    private func applyFiatTextLayout(scale: CGFloat) {
        let fiatLayout = TextViewLayout(.initialize(string: fiatText ?? "—", color: walletCardSecondaryColor, font: walletCardRoundedFont(14.0 * scale)), maximumNumberOfLines: 1)
        fiatLayout.measure(width: .greatestFiniteMagnitude)
        fiatView.update(fiatLayout)
    }

    private func qrIconSize(scale: CGFloat) -> NSSize {
        return NSMakeSize(floor(walletCardQRChipReferenceSize.width * scale), floor(walletCardQRChipReferenceSize.height * scale))
    }

    private func updateQRChipImageIfNeeded(chipSize: NSSize) {
        let key = "\(chipSize.width)x\(chipSize.height)@\(backingScaleFactor)"
        guard key != qrChipImageKey else {
            return
        }
        qrChipImageKey = key
        qrChipRenderer = WalletCardQRChipRenderer(chipSize: chipSize, backingScale: backingScaleFactor)
        renderQRChip(force: true)
        updateSurfaceClock()
    }

    private func renderQRChip(force: Bool = false) {
        guard let qrChipRenderer, !isTransfer else {
            return
        }
        let surface = surfaceTilt
        let phase = 0.12 * sin(surfaceTime * 0.45)
        if !force, let rendered = qrChipRendered, abs(rendered.surface.x - surface.x) < 0.003, abs(rendered.surface.y - surface.y) < 0.003, abs(rendered.phase - phase) < 0.003 {
            return
        }
        qrChipRendered = (surface, phase)
        qrIconView.image = qrChipRenderer.image(surface: surface, time: surfaceTime)
    }

    private func updateSurfaceClock() {
        guard window != nil, !isTransfer, !reduceMotion, scrollCollapseFraction < 1.0, qrChipRenderer != nil else {
            surfaceClock?.isPaused = true
            return
        }
        if surfaceClock == nil {
            surfaceClock = ConstantDisplayLinkAnimator(framesPerSecond: .fps(60), update: { [weak self] duration in
                self?.surfaceClockTick(duration)
            })
        }
        surfaceClock?.isPaused = false
    }

    private func surfaceClockTick(_ duration: CGFloat) {
        surfaceTime += min(max(duration, 0.0), 1.0 / 30.0)
        renderQRChip()
        renderBevel()
    }

    private func renderBevel(force: Bool = false) {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else {
            return
        }
        let surface = surfaceTilt
        if !force, let rendered = bevelRenderedSurface, abs(rendered.x - surface.x) < 0.003, abs(rendered.y - surface.y) < 0.003 {
            return
        }
        bevelRenderedSurface = surface
        bevelLayer.contents = walletCardBevelImage(size: size, cornerRadius: 20.0 * size.width / 336.0, surface: surface)
    }

    private func qrButtonSize(scale: CGFloat) -> NSSize {
        let iconSize = qrIconSize(scale: scale)
        return NSMakeSize(max(50.0, iconSize.width), max(38.0, iconSize.height))
    }

    private var digitRollKey: String {
        return "\(integralText)|\(fractionalText)|\(fiatText ?? "")|\(appliedTextScale ?? 0)"
    }

    private func applyTextLayouts(scale: CGFloat, width: CGFloat) {
        if let roll = digitRolls.first, roll.key != digitRollKey {
            finishDigitRolls()
        }
        applyBalanceTextLayouts(scale: scale)
        applyFiatTextLayout(scale: scale)
        balanceScale = 1.0
        fiatScale = 1.0
        if !isTransfer {
            let fit = WalletCardBalanceFit(width: width, scale: scale, qrWidth: qrButtonSize(scale: scale).width, hasFractional: !fractionalText.isEmpty, balanceTextWidth: integralView.frame.width + fractionalView.frame.width + currencyView.frame.width, fiatWidth: fiatView.frame.width)
            balanceScale = fit.balanceScale
            fiatScale = fit.fiatScale
        }

        let nameLayout = TextViewLayout(.initialize(string: nameText, color: .white, font: .semiboldMonospace(14.0 * scale)), maximumNumberOfLines: 1)
        nameLayout.measure(width: max(1.0, width - 96.0 * scale))
        nameView.update(nameLayout)
        self.nameLayout = nameLayout

        let recipientLayout = TextViewLayout(.initialize(string: recipientText, color: .white, font: .semiboldMonospace(13.0 * scale)), maximumNumberOfLines: 2)
        recipientLayout.measure(width: max(1.0, width - 48.0 * scale))
        recipientView.update(recipientLayout)
    }

    private func updateAddressImageIfNeeded(scale: CGFloat) {
        let key = "\(address)|\(scale)|\(System.backingScale)"
        guard key != addressImageKey else {
            return
        }
        addressImageKey = key
        if let (image, size) = walletCardAddressImage(address, scale: scale) {
            addressView.image = image
            addressImageSize = size
        } else {
            addressView.image = nil
            addressImageSize = .zero
        }
        updateAddressReveal(force: true)
    }

    func prepareIntro() {
        guard introStart == nil, !introPending, !isTransfer, !reduceMotion else {
            return
        }
        introPending = true
    }

    func cancelIntro() {
        guard introPending else {
            return
        }
        introPending = false
        addressImageKey = nil
        needsLayout = true
    }

    func playIntro(at start: CFTimeInterval, pace: Double) {
        guard introStart == nil, !isTransfer else {
            return
        }
        introStart = start
        introPending = false
        addressImageKey = nil
        let now = CACurrentMediaTime()
        let balanceDuration = WalletHomeIntro.balanceDuration * pace
        let fiatDelay = WalletHomeIntro.fiatDelay * pace
        guard !reduceMotion, window != nil, now < start + balanceDuration else {
            needsLayout = true
            return
        }
        let width = frame.width
        if width > 0, let scale = appliedTextScale {
            updateAddressImageIfNeeded(scale: scale)
            if !address.isEmpty {
                let reveal = WalletAddressReveal(startTime: start, scrambleDuration: WalletHomeIntro.addressScrambleDuration * pace, speed: 1 / pace)
                addressReveal = reveal
                updateAddressReveal(force: true)
                reveal.addFade(to: addressView.layer)
            }
            let key = digitRollKey
            let hasFraction = !fractionalText.isEmpty && !fractionalView.isHidden
            let rolls: [(TextView, CFTimeInterval, Double, Int)] = [
                (integralView, start, balanceDuration, hasFraction ? 1 : 2),
                (fractionalView, start, balanceDuration, 2),
                (fiatView, start + fiatDelay, balanceDuration - fiatDelay, 2)
            ]
            digitRolls = rolls.compactMap { textView, time, duration, turns in
                guard !textView.isHidden, let roll = WalletDigitRoll(textView: textView, key: key, mode: .fullTurns(rightmost: turns)) else {
                    return nil
                }
                roll.play(at: time, duration: duration, timingFunction: CAMediaTimingFunction(controlPoints: 0.3, 0.0, 0.2, 1.0))
                return roll
            }
        } else {
            needsLayout = true
        }
        let animator = ConstantDisplayLinkAnimator(update: { [weak self] in
            self?.introTick()
        }, fps: 60)
        animator.isPaused = false
        introAnimator = animator
    }

    private func introTick() {
        guard introStart != nil else {
            finishIntro()
            return
        }
        let now = CACurrentMediaTime()
        if let endTime = digitRolls.compactMap(\.endTime).max(), now >= endTime {
            finishDigitRolls()
        }
        addressReveal?.advance(to: now)
        updateAddressReveal(force: false)
        if digitRolls.isEmpty, addressReveal == nil {
            introAnimator?.invalidate()
            introAnimator = nil
        }
    }

    private func finishDigitRolls() {
        for roll in digitRolls {
            roll.remove()
        }
        digitRolls = []
    }

    private func finishIntro() {
        introPending = false
        finishDigitRolls()
        introAnimator?.invalidate()
        introAnimator = nil
        if addressReveal != nil {
            addressReveal = nil
            addressView.layer?.removeAnimation(forKey: WalletAddressReveal.fadeKey)
            addressImageKey = nil
            needsLayout = true
        }
    }

    private func updateAddressReveal(force: Bool) {
        guard let reveal = addressReveal else {
            return
        }
        let scale = frame.width / walletCardReferenceSize.width
        guard !reveal.isFinished else {
            addressReveal = nil
            addressView.image = walletCardAddressImage(address, scale: scale)?.0
            return
        }
        let text = walletCardAddressLines(address).joined(separator: "\n")
        guard let characters = reveal.characters(for: text, force: force) else {
            return
        }
        var lines: [[(character: Character, isSettled: Bool)]] = [[]]
        for (character, isSettled) in characters {
            if character == "\n" {
                lines.append([])
            } else {
                lines[lines.count - 1].append((character: Character(String(character).uppercased()), isSettled: isSettled))
            }
        }
        addressView.image = walletCardAddressImage(lines: lines, scale: scale)?.0
    }

    public override func layout() {
        super.layout()

        let width = frame.width
        let height = frame.height
        guard width > 0, height > 0 else {
            return
        }

        let scale = width / (isTransfer ? walletTransferCardReferenceSize.width : walletCardReferenceSize.width)
        let unit = width / 336.0

        edgeView.frame = bounds
        edgeView.layer?.cornerRadius = 20.0 * unit
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeGradientLayer.frame = bounds
        CATransaction.commit()
        faceView.frame = bounds
        faceView.layer?.cornerRadius = 20.0 * unit
        effectsLayer.frame = bounds
        bevelLayer.frame = bounds
        bevelMaskLayer.frame = bounds
        bevelMaskLayer.cornerRadius = 20.0 * unit
        let bevelKey = "\(bounds.size.width)x\(bounds.size.height)"
        if bevelKey != bevelImageKey {
            bevelImageKey = bevelKey
            renderBevel(force: true)
        }

        if appliedTextScale != scale {
            appliedTextScale = scale
            applyTextLayouts(scale: scale, width: width)
        }

        let mainCenterY = 94.0 * scale
        let integralHeight = integralView.frame.height * balanceScale
        var mainOriginX = 20.0 * scale
        let integralY: CGFloat
        if isTransfer {
            if gramIconNativeSize.width > 0, gramIconNativeSize.height > 0 {
                gramIconView.setFrameSize(NSMakeSize(floor(gramIconNativeSize.width * scale), floor(gramIconNativeSize.height * scale)))
            }
            integralY = floorToScreenPixels(backingScaleFactor, mainCenterY - integralHeight / 2)
            gramIconView.setFrameOrigin(NSMakePoint(mainOriginX, integralY - 1.0 * scale))
            mainOriginX += gramIconView.frame.width
        } else {
            let layout = WalletCardDiamondLayout(scale: scale, balanceScale: balanceScale)
            integralY = floorToScreenPixels(backingScaleFactor, mainCenterY - max(layout.gramIconFrame.height, integralHeight) / 2)
            gramIconView.frame = layout.gramIconFrame
            mainOriginX = layout.balanceOriginX
        }
        let mainBaselineY = integralY + walletCardTextBaseline(integralView) * balanceScale
        integralView.setFrameOrigin(NSMakePoint(mainOriginX, integralY))
        mainOriginX += integralView.frame.width * balanceScale

        fractionalView.isHidden = fractionalText.isEmpty
        if !fractionalText.isEmpty {
            mainOriginX += 1.0 * scale * balanceScale
            fractionalView.setFrameOrigin(NSMakePoint(mainOriginX, mainBaselineY - walletCardTextBaseline(fractionalView) * balanceScale))
            mainOriginX += fractionalView.frame.width * balanceScale
        }
        mainOriginX += 5.0 * scale * balanceScale
        currencyView.setFrameOrigin(NSMakePoint(mainOriginX, mainBaselineY - walletCardTextBaseline(currencyView) * balanceScale))

        fiatView.setFrameOrigin(NSMakePoint(24.0 * scale, 114.0 * scale))
        applyCardTilt()

        var moneyZone = gramIconView.frame
        moneyZone = moneyZone.union(walletCardScaledFrame(integralView, balanceScale))
        if !fractionalText.isEmpty {
            moneyZone = moneyZone.union(walletCardScaledFrame(fractionalView, balanceScale))
        }
        moneyZone = moneyZone.union(walletCardScaledFrame(currencyView, balanceScale))
        let fiatZone = walletCardScaledFrame(fiatView, fiatScale)

        #if arch(arm64)
        let diamondLayout = WalletCardDiamondLayout(scale: scale, balanceScale: balanceScale)
        gramDiamondView.frame = diamondLayout.diamondFrame
        gramDiamondView.starContainer = bounds.offsetBy(dx: -diamondLayout.diamondFrame.minX, dy: -diamondLayout.diamondFrame.minY)
        gramDiamondView.update(size: diamondLayout.diamondFrame.size, diamondWidth: diamondLayout.diamondWidth, isVisible: !isTransfer && scrollCollapseFraction < 1.0, lightBackground: false, appearance: .white, expansionStyle: .wallet, tapToSpin: true)
        updateDiamondInteraction()
        updateDiamondTilt()
        if gramDiamondView.isExpanded {
            updateDiamondRefraction()
        }
        #endif

        if isTransfer {
            recipientView.setFrameOrigin(NSMakePoint(24.0 * scale, floorToScreenPixels(backingScaleFactor, 178.0 * scale - recipientView.frame.height / 2)))
            let infoIconSize: NSSize
            if let infoImage = infoIconView.image {
                infoIconSize = NSMakeSize(floor(infoImage.backingSize.width * scale), floor(infoImage.backingSize.height * scale))
            } else {
                infoIconSize = NSMakeSize(50.0 * scale, 38.0 * scale)
            }
            let infoButtonSize = NSMakeSize(max(50.0, infoIconSize.width), max(38.0, infoIconSize.height))
            infoButton.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, width - 32.0 * scale - infoButtonSize.width), floorToScreenPixels(backingScaleFactor, 82.0 * scale), infoButtonSize.width, infoButtonSize.height)
            infoIconView.frame = infoButton.bounds.focus(infoIconSize)
            effects.layout(bounds: bounds, unit: unit, safeZones: [moneyZone, fiatZone, recipientView.frame, infoButton.frame], backingScale: backingScaleFactor)
            effects.apply(tilt: tiltCurrent)
            return
        }

        nameView.setFrameOrigin(NSMakePoint(24.0 * scale, height - nameView.frame.height - 19.0 * scale))

        let qrButtonSize = self.qrButtonSize(scale: scale)
        qrButton.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, width - qrButtonSize.width - 47.0 * scale), floorToScreenPixels(backingScaleFactor, 82.0 * scale), qrButtonSize.width, qrButtonSize.height)
        let qrChipFrame = qrButton.bounds.focus(self.qrIconSize(scale: scale))
        qrIconView.frame = qrChipFrame.insetBy(dx: -walletCardQRChipMargin * qrChipFrame.width / walletCardQRChipReferenceSize.width, dy: -walletCardQRChipMargin * qrChipFrame.height / walletCardQRChipReferenceSize.height)
        updateQRChipImageIfNeeded(chipSize: qrChipFrame.size)

        updateAddressImageIfNeeded(scale: scale)
        let addressCenterX = width - addressImageSize.width - 7.0 * scale
        addressView.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, addressCenterX - addressImageSize.width / 2), floorToScreenPixels(backingScaleFactor, height / 2 - addressImageSize.height / 2), addressImageSize.width, addressImageSize.height)

        let safeZones = [moneyZone, fiatZone, nameView.frame, qrButton.frame, addressView.frame]
        effects.layout(bounds: bounds, unit: unit, safeZones: safeZones, backingScale: backingScaleFactor)
        effects.apply(tilt: tiltCurrent)
    }
}

@available(macOS 10.15, *)
extension WalletCardView: WalletIntroParticipant {}

#if arch(arm64)
private func walletDiamondRefractionTexture(_ image: CGImage) -> MTLTexture? {
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = bytes.withUnsafeMutableBytes { storage -> Bool in
        guard let context = CGContext(data: storage.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            return false
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    descriptor.usage = .shaderRead
    guard drawn, let texture = MetalEngine.shared.device.makeTexture(descriptor: descriptor) else {
        return nil
    }
    bytes.withUnsafeBytes { storage in
        if let base = storage.baseAddress {
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: base, bytesPerRow: width * 4)
        }
    }
    return texture
}
#endif

func walletChatCardShimmerBandPoints(width: CGFloat, size: NSSize) -> (start: (from: NSPoint, to: NSPoint), end: (from: NSPoint, to: NSPoint)) {
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        return NSMakePoint((x - 4) / size.width, (y - 4) / size.height)
    }
    let cardWidth = size.width + 8
    let fromX = -0.6 * cardWidth
    let toX = 1.6 * cardWidth
    return ((point(fromX - width, 0), point(toX - width, 0)), (point(fromX + width, width * 0.7), point(toX + width, width * 0.7)))
}

@available(macOS 10.15, *)
private final class WalletChatCardShimmerView: View {
    let repeatAnimation: Bool
    let followsArrival: Bool
    var completion: (() -> Void)?

    private let surfaceLayer = CAGradientLayer()
    private let borderGlowLayer = CAGradientLayer()
    private let borderLayer = CAGradientLayer()
    private let borderGlowMaskLayer = CAShapeLayer()
    private let borderMaskLayer = CAShapeLayer()
    private let addressView = View()
    private let addressLayer = CAGradientLayer()
    private let addressMaskLayer = CALayer()
    private var currentLayout: (size: NSSize, addressFrame: NSRect)?
    private var animationStartTime: CFTimeInterval?

    init(frame frameRect: NSRect, repeatAnimation: Bool, followsArrival: Bool = false) {
        self.repeatAnimation = repeatAnimation
        self.followsArrival = followsArrival
        super.init(frame: frameRect)
        isEventLess = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 20
        layer?.cornerCurve = .continuous

        for (mask, width) in [(borderGlowMaskLayer, CGFloat(4.5)), (borderMaskLayer, CGFloat(1.3))] {
            mask.fillColor = NSColor.clear.cgColor
            mask.strokeColor = NSColor.white.cgColor
            mask.lineWidth = width
            mask.contentsScale = System.backingScale
        }
        borderGlowLayer.mask = borderGlowMaskLayer
        borderLayer.mask = borderMaskLayer
        addressMaskLayer.contentsGravity = .resizeAspect
        addressView.isEventLess = true
        addressView.layer?.mask = addressMaskLayer
        addressView.layer?.addSublayer(addressLayer)

        let bands: [(CAGradientLayer, NSColor, CGFloat)] = [
            (surfaceLayer, .white, 0.07),
            (borderGlowLayer, .white, 0.28),
            (borderLayer, .white, 0.55),
            (addressLayer, NSColor(red: 0.36, green: 0.86, blue: 1.0, alpha: 1.0), 0.9)
        ]
        for (band, color, peak) in bands {
            band.colors = [0.0, 0.18, 0.6, 1.0, 0.6, 0.18, 0.0].map { color.withAlphaComponent(peak * $0).cgColor }
            band.locations = [0.0, 0.22, 0.4, 0.5, 0.6, 0.78, 1.0]
            band.opacity = 0
        }
        for band in [surfaceLayer, borderGlowLayer, borderLayer] {
            layer?.addSublayer(band)
        }
        addSubview(addressView)
        surfaceLayer.compositingFilter = "screenBlendMode"
        borderGlowLayer.compositingFilter = "plusL"
        borderLayer.compositingFilter = "plusL"
    }

    public required convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, repeatAnimation: true)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(size: NSSize, addressFrame: NSRect, addressMask: CGImage?) {
        addressMaskLayer.contents = addressMask
        addressView.isHidden = followsArrival || addressMask == nil
        guard size.width > 0, size.height > 0 else {
            return
        }
        if let currentLayout, currentLayout.size == size, currentLayout.addressFrame == addressFrame {
            return
        }
        currentLayout = (size, addressFrame)
        let startTime: CFTimeInterval
        if let animationStartTime {
            startTime = animationStartTime
        } else {
            startTime = CACurrentMediaTime() + 0.15
            animationStartTime = startTime
        }

        let bounds = NSRect(origin: .zero, size: size)
        frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for band in [surfaceLayer, borderGlowLayer, borderLayer] {
            band.frame = bounds
        }
        let borderPath = CGPath(roundedRect: bounds, cornerWidth: 20, cornerHeight: 20, transform: nil)
        for mask in [borderGlowMaskLayer, borderMaskLayer] {
            mask.frame = bounds
            mask.path = borderPath
        }
        addressView.frame = addressFrame
        addressMaskLayer.frame = NSRect(origin: .zero, size: addressFrame.size)
        addressLayer.frame = bounds.offsetBy(dx: -addressFrame.minX, dy: -addressFrame.minY)
        CATransaction.commit()

        if followsArrival {
            return
        }

        for (band, width) in [(surfaceLayer, CGFloat(160)), (borderGlowLayer, CGFloat(128)), (borderLayer, CGFloat(112)), (addressLayer, CGFloat(112))] {
            animateBand(band, width: width, size: size, startTime: startTime)
        }
    }

    func updateArrival(time: Double) {
        guard followsArrival, bounds.width > 0, bounds.height > 0 else {
            return
        }
        let x = WalletTransferArrivalAnimation.sheenX(time)
        for (band, width) in [(surfaceLayer, CGFloat(160)), (borderGlowLayer, CGFloat(128)), (borderLayer, CGFloat(112))] {
            band.opacity = x == nil ? 0 : 1
            if let x {
                let points = WalletTransferArrivalAnimation.cardSheenBand(x: x, width: width, size: bounds.size)
                band.startPoint = points.start
                band.endPoint = points.end
            }
        }
    }

    private func animateBand(_ band: CAGradientLayer, width: CGFloat, size: NSSize, startTime: CFTimeInterval) {
        let points = walletChatCardShimmerBandPoints(width: width, size: size)
        let duration = 1.46
        let passFraction = NSNumber(value: 0.96 / duration)
        let ease = CAMediaTimingFunction(controlPoints: 1.0 / 3.0, 0.0, 2.0 / 3.0, 1.0)
        var animations: [CAAnimation] = []
        for (keyPath, from, to) in [
            ("startPoint", points.start.from, points.start.to),
            ("endPoint", points.end.from, points.end.to)
        ] {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = [NSValue(point: from), NSValue(point: to), NSValue(point: to)]
            animation.keyTimes = [0, passFraction, 1]
            animation.timingFunctions = [ease, CAMediaTimingFunction(name: .linear)]
            animation.duration = duration
            animations.append(animation)
        }
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [1.0, 0.0, 0.0]
        opacity.keyTimes = [0, passFraction, 1]
        opacity.calculationMode = .discrete
        opacity.duration = duration
        animations.append(opacity)

        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.beginTime = band.convertTime(startTime, from: nil)
        group.repeatCount = repeatAnimation ? .infinity : 0
        if !repeatAnimation, band === surfaceLayer {
            group.delegate = CALayerAnimationDelegate(completion: { [weak self] finished in
                if finished {
                    self?.completion?()
                }
            })
        }
        band.add(group, forKey: "shimmer")
    }
}

@available(macOS 10.15, *)
public final class WalletChatCardView: View {
    #if arch(arm64)
    private struct BackgroundRotationAnimation {
        let duration: CFTimeInterval
        let turns: CGFloat
        var start: (time: CFTimeInterval, offset: CGFloat)?
    }
    #endif

    public var onDiamondLanding: ((CGFloat) -> Void)?
    private let faceView = View()
    private let backgroundLayer = SimpleLayer()
    private let gramIconView = ImageView()
    #if arch(arm64)
    private var gramDiamondView = InteractiveDiamondView(frame: NSMakeRect(0, 0, walletChatCardDiamondCanvas, walletChatCardDiamondCanvas))
    private var amountText: NSAttributedString?
    private var refractionAmountText: NSAttributedString?
    private var isPendingTransfer = false
    private var isSendingTransfer = false
    private var isAwaitingTransferFlight = false
    private var isCovered = false
    private var isDiamondRendering: Bool {
        return !isAwaitingTransferFlight && !isCovered
    }
    private var backgroundRotation: CGFloat = 0
    private var backgroundMotion: (rotation: CGFloat, time: CFTimeInterval)?
    private var isBackgroundMotionActive = false
    private var backgroundRotationAnimation: BackgroundRotationAnimation?
    #else
    private let gramAnimationView = LottiePlayerView(frame: NSMakeRect(0, 0, walletChatCardGramAnimationSide, walletChatCardGramAnimationSide))
    #endif
    private let amountView = TextView()
    private let nameView = TextView()
    private let addressView = TextView()
    private let addressHighlightView = TextView()
    private var shimmerView: WalletChatCardShimmerView?
    private var arrivalTextView: WalletChatCardArrivalTextView?
    private var arrivalStartTime: CFTimeInterval?
    private var arrivalDidLand = false
    public var onArrivalInterrupted: (() -> Void)?
    private var addressText = ""
    private var addressMaskImage: (text: String, image: CGImage)?
    #if !arch(arm64)
    private var didStartAnimation = false
    private var isGramAnimationLooping = false
    private let gramAnimationStateDisposable = MetaDisposable()
    #endif

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        self.backgroundColor = .clear
        self.isEventLess = true

        faceView.backgroundColor = walletCardBaseColor
        faceView.layer?.cornerCurve = .continuous
        faceView.layer?.masksToBounds = true
        backgroundLayer.contents = NSImage(named: "Wallet_ChatCardBackground")?._cgImage
        backgroundLayer.contentsGravity = .resize
        faceView.layer?.addSublayer(backgroundLayer)
        faceView.isEventLess = true
        addSubview(faceView)

        for textView in [amountView, nameView, addressHighlightView, addressView] {
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            textView.disableBackgroundDrawing = true
            textView.isEventLess = true
            faceView.addSubview(textView)
        }

        gramIconView.isEventLess = true
        gramIconView.contentGravity = .resizeAspect
        #if arch(arm64)
        gramIconView.isHidden = true
        gramIconView.setFrameSize(NSMakeSize(walletChatCardDiamondSide, walletChatCardDiamondSide))
        #else
        gramIconView.image = walletGramIcon(walletChatCardGramIconSide)
        gramIconView.setFrameSize(NSMakeSize(walletChatCardGramIconSide, walletChatCardGramIconSide))
        #endif
        faceView.addSubview(gramIconView)

        #if arch(arm64)
        installDiamond()
        #else
        gramAnimationView.isEventLess = true
        faceView.addSubview(gramAnimationView)
        #endif
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    #if !arch(arm64)
    deinit {
        gramAnimationStateDisposable.dispose()
    }
    #endif

    public func update(amount: Int64, isIncoming: Bool, name: String, address: String) {
        let sign = isIncoming ? "+" : "−"
        let value = formatTonAmountText(amount, maxDecimalPositions: 3)
        let formatted = sign + value
        let amountText = NSMutableAttributedString(attributedString: tonAmountAttributedString(
            formatted,
            integralFont: walletCardRoundedFont(18, monospacedDigits: false),
            fractionalFont: walletCardRoundedFont(14, monospacedDigits: false),
            color: .white
        ))
        let unit = value == "1" ? strings().walletCardViewGramUnit : strings().walletCardViewGramsUnit
        amountText.append(.initialize(string: unit, color: NSColor(rgb: 0x0fddff), font: walletCardRoundedFont(18, monospacedDigits: false)))
        let amountLayout = TextViewLayout(amountText, maximumNumberOfLines: 1)
        amountLayout.measure(width: frame.width - 24)
        amountView.update(amountLayout)
        #if arch(arm64)
        self.amountText = amountText
        #endif

        let nameLayout = TextViewLayout(.initialize(string: name.uppercased(), color: NSColor(rgb: 0x0bdbff), font: .semiboldMonospace(12)), maximumNumberOfLines: 1)
        nameLayout.measure(width: frame.width - 30)
        nameView.update(nameLayout)

        let addressText = walletTransferCardRecipientText(address)
        let addressLayout = TextViewLayout(.initialize(string: addressText, color: NSColor(rgb: 0x0036b2), font: .normalMonospaced(10)), maximumNumberOfLines: 2, alignment: .center)
        addressLayout.measure(width: frame.width - 24)
        addressView.update(addressLayout)
        addressView.isHidden = address.isEmpty
        let addressHighlightLayout = TextViewLayout(.initialize(string: addressText, color: NSColor.white.withAlphaComponent(0.06), font: .normalMonospaced(10)), maximumNumberOfLines: 2, alignment: .center)
        addressHighlightLayout.measure(width: frame.width - 24)
        addressHighlightView.update(addressHighlightLayout)
        addressHighlightView.isHidden = address.isEmpty
        self.addressText = address.isEmpty ? "" : addressText

        needsLayout = true
    }

    private func currentAddressMaskImage() -> CGImage? {
        guard !addressText.isEmpty, addressView.frame.width > 0, addressView.frame.height > 0 else {
            return nil
        }
        if let cached = addressMaskImage, cached.text == addressText {
            return cached.image
        }
        let node = TextNode.layoutText(.initialize(string: addressText, color: .white, font: .normalMonospaced(10)), nil, 2, .end, NSMakeSize(frame.width - 24, .greatestFiniteMagnitude), nil, false, .center)
        guard let image = generateImage(addressView.frame.size, rotatedContext: { size, ctx in
            ctx.clear(size.bounds)
            node.1.draw(size.bounds.focus(node.0.size), in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
        }) else {
            return nil
        }
        addressMaskImage = (addressText, image)
        return image
    }

    #if arch(arm64)
    private func installDiamond() {
        gramDiamondView.onExpansionChanged = { [weak self] isExpanded in
            guard let self else {
                return
            }
            if isExpanded {
                if self.arrivalTextView != nil {
                    self.onArrivalInterrupted?()
                }
                if self.backgroundRotationAnimation != nil {
                    self.backgroundRotationAnimation = BackgroundRotationAnimation(duration: 0.22, turns: 0)
                }
                self.backgroundMotion = nil
            }
            self.updateDiamondRefraction()
        }
        gramDiamondView.onMotionUpdated = { [weak self] state in
            self?.updateBackgroundRotation(state)
        }
        gramDiamondView.onLanding = { [weak self] power in
            self?.onDiamondLanding?(power)
        }
        faceView.addSubview(gramDiamondView)
    }

    private func layoutDiamond() {
        let gramIconFrame = gramIconView.frame
        gramDiamondView.frame = NSMakeRect(gramIconFrame.midX - walletChatCardDiamondCanvas / 2, gramIconFrame.midY - walletChatCardDiamondCanvas / 2, walletChatCardDiamondCanvas, walletChatCardDiamondCanvas)
        gramDiamondView.isHidden = isAwaitingTransferFlight
        gramDiamondView.update(size: NSMakeSize(walletChatCardDiamondCanvas, walletChatCardDiamondCanvas), diamondWidth: walletChatCardDiamondSide, isVisible: isDiamondRendering, lightBackground: false, appearance: .cool, expansionStyle: .downward, tapToSpin: true)
    }

    public func updateTransferState(isSending: Bool, isPending: Bool, animateCompletion: Bool) {
        isPendingTransfer = isPending
        isSendingTransfer = isSending
        if isSending {
            backgroundRotationAnimation = nil
        } else {
            backgroundRotationAnimation = BackgroundRotationAnimation(duration: animateCompletion ? 1.8 : 0.22, turns: animateCompletion ? 2 : 0)
        }
        gramDiamondView.isInteractionEnabled = !isSending && !isAwaitingTransferFlight
        gramDiamondView.updateTransferState(isSending: isSending, animateCompletion: animateCompletion)
    }

    public func resetTransferState() {
        stopBackgroundMotion()
        isPendingTransfer = false
        isSendingTransfer = false
        backgroundRotation = 0
        backgroundLayer.transform = CATransform3DIdentity
        setAwaitingTransferFlight(false, animated: false)
        gramDiamondView.isInteractionEnabled = true
        gramDiamondView.updateTransferState(isSending: false, animateCompletion: false)
    }

    public func setAwaitingTransferFlight(_ awaiting: Bool, animated: Bool) {
        guard isAwaitingTransferFlight != awaiting else {
            return
        }
        isAwaitingTransferFlight = awaiting
        stopBackgroundMotion()
        gramDiamondView.isHidden = awaiting
        gramDiamondView.isRenderingEnabled = isDiamondRendering
        gramDiamondView.isInteractionEnabled = !awaiting && !isSendingTransfer
        if awaiting {
            gramDiamondView.updateTransferState(isSending: false, animateCompletion: false)
        } else if animated {
            gramDiamondView.layer?.animateAlpha(from: 0, to: 1, duration: 0.15)
        }
    }

    public func setCovered(_ covered: Bool) {
        guard isCovered != covered else {
            return
        }
        isCovered = covered
        gramDiamondView.isRenderingEnabled = isDiamondRendering
    }

    public func transferDiamondTarget(in view: NSView) -> (center: NSPoint, width: CGFloat)? {
        guard let window, window === view.window, bounds.width > 0 else {
            return nil
        }
        let center = NSMakePoint(gramIconView.frame.midX, gramIconView.frame.midY)
        let point = view.convert(center, from: faceView)
        let left = view.convert(NSMakePoint(center.x - walletChatCardDiamondSide / 2, center.y), from: faceView)
        let right = view.convert(NSMakePoint(center.x + walletChatCardDiamondSide / 2, center.y), from: faceView)
        return (point, hypot(right.x - left.x, right.y - left.y))
    }

    public func acceptTransferDiamond(_ diamond: InteractiveDiamondView) {
        gramDiamondView.onMotionUpdated = nil
        gramDiamondView.isRenderingEnabled = false
        gramDiamondView.removeFromSuperview()
        gramDiamondView = diamond
        isAwaitingTransferFlight = false
        diamond.alphaValue = 1
        installDiamond()
        layoutDiamond()
        diamond.updateTransferState(isSending: true, animateCompletion: false)
        diamond.spin(4.5, decay: 0.7)
    }

    private func stopBackgroundMotion() {
        isBackgroundMotionActive = false
        backgroundRotationAnimation = nil
        backgroundMotion = nil
    }

    private func updateBackgroundRotation(_ state: InteractiveDiamondView.MotionState?) {
        guard let state, window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, !isAwaitingTransferFlight else {
            stopBackgroundMotion()
            return
        }
        if !isBackgroundMotionActive {
            isBackgroundMotionActive = true
            if backgroundRotationAnimation == nil {
                backgroundRotationAnimation = BackgroundRotationAnimation(duration: 0.22, turns: 0)
            }
        }

        let rotation: CGFloat
        if let transferEnergy = state.transferEnergy, isPendingTransfer || (arrivalStartTime != nil && !arrivalDidLand) {
            backgroundRotationAnimation = nil
            defer {
                backgroundMotion = (state.rotation, state.time)
            }
            guard let previous = backgroundMotion, state.time >= previous.time else {
                return
            }
            let delta = state.rotation - previous.rotation
            let energy = min(1, max(0, transferEnergy))
            let step = atan2(sin(delta), cos(delta)) * 2 * (1 - 0.5 * energy) + 0.12 * CGFloat(state.time - previous.time)
            rotation = backgroundRotation + step
        } else {
            backgroundMotion = nil
            if var animation = backgroundRotationAnimation {
                let start: (time: CFTimeInterval, offset: CGFloat)
                if let current = animation.start {
                    start = current
                } else {
                    start = (state.time, atan2(sin(backgroundRotation), cos(backgroundRotation)) - animation.turns * 2 * .pi)
                    animation.start = start
                }
                let progress = CGFloat(min(1, max(0, (state.time - start.time) / animation.duration)))
                let remaining = 1 - progress
                rotation = start.offset * remaining * remaining * remaining
                backgroundRotationAnimation = progress < 1 ? animation : nil
            } else {
                rotation = 0
            }
        }
        let normalizedRotation = rotation.truncatingRemainder(dividingBy: 2 * .pi)
        guard backgroundRotation != normalizedRotation else {
            return
        }
        backgroundRotation = normalizedRotation
        backgroundLayer.transform = CATransform3DMakeRotation(normalizedRotation, 0, 0, 1)
    }

    private func updateDiamondRefraction() {
        refractionAmountText = amountText
        guard gramDiamondView.isExpanded, let amountText, amountView.frame.width > 0, amountView.frame.height > 0 else {
            gramDiamondView.updateRefractionSource(nil)
            return
        }
        let scale = backingScaleFactor
        let sourceRect = amountView.frame.insetBy(dx: -2, dy: -2).integral
        let node = TextNode.layoutText(amountText, nil, 1, .end, NSMakeSize(frame.width - 24, .greatestFiniteMagnitude), nil, false, .left)
        let textOrigin = NSMakePoint(amountView.frame.minX - sourceRect.minX, amountView.frame.minY - sourceRect.minY)
        guard let image = generateImage(sourceRect.size, scale: scale, rotatedContext: { size, ctx in
            ctx.clear(size.bounds)
            node.1.draw(NSRect(origin: textOrigin, size: node.0.size), in: ctx, backingScaleFactor: scale, backgroundColor: .clear)
        }) else {
            gramDiamondView.updateRefractionSource(nil)
            return
        }
        guard let texture = walletDiamondRefractionTexture(image) else {
            gramDiamondView.updateRefractionSource(nil)
            return
        }
        let rect = sourceRect.offsetBy(dx: -gramDiamondView.frame.midX, dy: -gramDiamondView.frame.midY)
        gramDiamondView.updateRefractionSource(InteractiveDiamondView.RefractionSource(texture: texture, uv: SIMD4(0, 0, 1, 1), rect: rect, preservesColors: true))
    }
    #else
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        startAnimationIfNeeded()
    }

    private func startAnimationIfNeeded() {
        guard window != nil, !didStartAnimation else {
            return
        }
        guard let url = Bundle.module.url(forResource: "GramDiamondLight", withExtension: "tgs"), let data = try? Data(contentsOf: url) else {
            return
        }
        didStartAnimation = true
        gramIconView.isHidden = true
        let size = NSMakeSize(walletChatCardGramAnimationSide, walletChatCardGramAnimationSide)
        gramAnimationView.set(LottieAnimation(compressed: data, key: .init(key: .bundle("GramDiamondLight"), size: size), cachePurpose: .temporaryLZ4(.thumb), playPolicy: .onceEnd, maximumFps: 60))
        gramAnimationStateDisposable.set((gramAnimationView.state |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let self, state == .finished, self.isGramAnimationLooping else {
                return
            }
            self.gramAnimationView.playAgain()
        }))
    }

    public func updateTransferState(isSending: Bool, isPending: Bool, animateCompletion: Bool) {
        isGramAnimationLooping = isSending
        if isSending, gramAnimationView.currentState == .finished {
            gramAnimationView.playAgain()
        }
    }

    public func resetTransferState() {
        isGramAnimationLooping = false
    }

    public func setAwaitingTransferFlight(_ awaiting: Bool, animated: Bool) {
    }

    public func setCovered(_ covered: Bool) {
    }

    public func transferDiamondTarget(in view: NSView) -> (center: NSPoint, width: CGFloat)? {
        return nil
    }

    public func acceptTransferDiamond(_ diamond: InteractiveDiamondView) {
    }
    #endif

    public var isDiamondExpanded: Bool {
        #if arch(arm64)
        return gramDiamondView.isExpanded
        #else
        return false
        #endif
    }

    public func prepareIncomingTransferAnimation() {
        guard arrivalTextView == nil else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shimmerView?.removeFromSuperview()
        shimmerView = nil
        let text = WalletChatCardArrivalTextView(frame: bounds)
        arrivalTextView = text
        faceView.addSubview(text)
        text.update(views: [amountView, nameView, addressView])
        for view in [amountView, nameView, addressView, addressHighlightView] {
            view.alphaValue = 0
        }
        updateArrivalShimmer()
        CATransaction.commit()
    }

    @discardableResult
    public func updateIncomingTransferAnimation(startTime: CFTimeInterval, at timestamp: CFTimeInterval) -> Double {
        prepareIncomingTransferAnimation()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if arrivalStartTime == nil {
            arrivalStartTime = startTime
            #if arch(arm64)
            backgroundRotationAnimation = nil
            backgroundMotion = nil
            gramDiamondView.beginReceivingTransfer(at: startTime, completionDelay: WalletTransferArrivalAnimation.landing)
            #endif
        }
        let t = max(0, timestamp - startTime)
        arrivalTextView?.update(time: t)
        shimmerView?.updateArrival(time: t)
        if t >= WalletTransferArrivalAnimation.landing, !arrivalDidLand {
            arrivalDidLand = true
            #if arch(arm64)
            backgroundRotationAnimation = BackgroundRotationAnimation(duration: 1.8, turns: 2)
            #endif
        }
        CATransaction.commit()
        return t - WalletTransferArrivalAnimation.landing
    }

    public func finishIncomingTransferAnimation() {
        guard let text = arrivalTextView else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arrivalTextView = nil
        text.removeFromSuperview()
        arrivalStartTime = nil
        arrivalDidLand = false
        for view in [amountView, nameView, addressView, addressHighlightView] {
            view.alphaValue = 1
        }
        shimmerView?.removeFromSuperview()
        shimmerView = nil
        #if arch(arm64)
        gramDiamondView.endReceivingTransfer()
        backgroundMotion = nil
        backgroundRotationAnimation = BackgroundRotationAnimation(duration: 0.22, turns: 0)
        #endif
        CATransaction.commit()
    }

    private func updateArrivalShimmer() {
        guard let text = arrivalTextView else {
            return
        }
        let shimmerView: WalletChatCardShimmerView
        if let current = self.shimmerView, current.followsArrival {
            shimmerView = current
        } else {
            self.shimmerView?.removeFromSuperview()
            shimmerView = WalletChatCardShimmerView(frame: bounds, repeatAnimation: false, followsArrival: true)
            self.shimmerView = shimmerView
            faceView.addSubview(shimmerView, positioned: .below, relativeTo: text)
        }
        shimmerView.update(size: bounds.size, addressFrame: addressView.frame, addressMask: nil)
        #if arch(arm64)
        faceView.addSubview(gramDiamondView)
        #else
        faceView.addSubview(gramAnimationView)
        #endif
    }

    public func updateShimmer(visible: Bool, repeating: Bool, animated: Bool, completion: (() -> Void)?) {
        if arrivalTextView != nil {
            updateArrivalShimmer()
            return
        }
        if visible {
            let shimmerView: WalletChatCardShimmerView
            if let current = self.shimmerView, current.repeatAnimation == repeating {
                shimmerView = current
            } else {
                self.shimmerView?.removeFromSuperview()
                shimmerView = WalletChatCardShimmerView(frame: bounds, repeatAnimation: repeating)
                self.shimmerView = shimmerView
                faceView.addSubview(shimmerView, positioned: .below, relativeTo: gramIconView)
                if !repeating {
                    #if arch(arm64)
                    Queue.mainQueue().after(0.18, { [weak self, weak shimmerView] in
                        guard let self, let shimmerView, self.shimmerView === shimmerView, self.window != nil else {
                            return
                        }
                        self.gramDiamondView.pushFromBelow(strength: 1.5)
                    })
                    #endif
                    shimmerView.completion = { [weak self, weak shimmerView] in
                        guard let self, let shimmerView, self.shimmerView === shimmerView else {
                            return
                        }
                        self.shimmerView = nil
                        shimmerView.removeFromSuperview()
                        completion?()
                    }
                }
            }
            shimmerView.layer?.removeAnimation(forKey: "opacity")
            shimmerView.layer?.opacity = 1
            shimmerView.update(size: bounds.size, addressFrame: addressView.frame, addressMask: currentAddressMaskImage())
        } else if let shimmerView = self.shimmerView {
            if animated, window != nil {
                guard shimmerView.layer?.opacity != 0 else {
                    return
                }
                shimmerView.layer?.opacity = 0
                let fadeValues = (0 ... 36).map { NSNumber(value: pow(1.0 - Double($0) / 36.0, 2.2)) }
                shimmerView.layer?.animateKeyframes(values: fadeValues, duration: 0.3, keyPath: "opacity", timingFunction: .linear, completion: { [weak self, weak shimmerView] finished in
                    guard finished, let self, let shimmerView, self.shimmerView === shimmerView, shimmerView.layer?.opacity == 0 else {
                        return
                    }
                    shimmerView.removeFromSuperview()
                    self.shimmerView = nil
                })
            } else {
                shimmerView.removeFromSuperview()
                self.shimmerView = nil
            }
        }
    }

    public override func layout() {
        super.layout()

        let width = frame.width
        let height = frame.height
        guard width > 0, height > 0 else {
            return
        }

        faceView.frame = bounds
        faceView.layer?.cornerRadius = 20
        backgroundLayer.bounds = NSMakeRect(0, 0, 380, 295)
        backgroundLayer.position = NSMakePoint(width / 2, height / 2)

        #if arch(arm64)
        gramIconView.setFrameOrigin(NSMakePoint(floorToScreenPixels(backingScaleFactor, (width - gramIconView.frame.width) / 2), 16))
        layoutDiamond()
        #else
        gramIconView.setFrameOrigin(NSMakePoint(floorToScreenPixels(backingScaleFactor, (width - gramIconView.frame.width) / 2), 18))
        let gramIconFrame = gramIconView.frame
        gramAnimationView.setFrameOrigin(NSMakePoint(floorToScreenPixels(backingScaleFactor, gramIconFrame.midX - walletChatCardGramAnimationSide / 2), floorToScreenPixels(backingScaleFactor, gramIconFrame.midY - walletChatCardGramAnimationSide / 2)))
        #endif
        amountView.setFrameOrigin(NSMakePoint(floorToScreenPixels(backingScaleFactor, (width - amountView.frame.width) / 2), 62))
        nameView.setFrameOrigin(NSMakePoint(floorToScreenPixels(backingScaleFactor, (width - nameView.frame.width) / 2), 97))
        addressView.setFrameOrigin(NSMakePoint(floorToScreenPixels(backingScaleFactor, (width - addressView.frame.width) / 2), 114))
        addressHighlightView.frame = addressView.frame.offsetBy(dx: 0, dy: 1)
        if let arrivalTextView {
            arrivalTextView.frame = bounds
            arrivalTextView.update(views: [amountView, nameView, addressView])
            shimmerView?.update(size: bounds.size, addressFrame: addressView.frame, addressMask: nil)
        } else {
            shimmerView?.update(size: bounds.size, addressFrame: addressView.frame, addressMask: currentAddressMaskImage())
        }
        #if arch(arm64)
        if gramDiamondView.isExpanded, refractionAmountText != amountText {
            updateDiamondRefraction()
        }
        #endif
    }
}
