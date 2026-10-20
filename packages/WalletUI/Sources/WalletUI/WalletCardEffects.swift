import Cocoa
import CoreImage
import TGUIKit
import TelegramTheme
import TelegramContext
import GeneralRows

public struct WalletCardTilt: Equatable {
    public var tx: CGFloat = 0
    public var ty: CGFloat = 0
    public init(tx: CGFloat = 0, ty: CGFloat = 0) {
        self.tx = tx
        self.ty = ty
    }
}

private func walletCardOklchColor(lightness: CGFloat, chroma: CGFloat, hueDegrees: CGFloat) -> CGColor {
    let hue = hueDegrees * .pi / 180.0
    let a = chroma * cos(hue)
    let b = chroma * sin(hue)

    let l_ = lightness + 0.3963377774 * a + 0.2158037573 * b
    let m_ = lightness - 0.1055613458 * a - 0.0638541728 * b
    let s_ = lightness - 0.0894841775 * a - 1.2914855480 * b

    let l = l_ * l_ * l_
    let m = m_ * m_ * m_
    let s = s_ * s_ * s_

    let linearR = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    let linearG = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    let linearB = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

    func gamma(_ value: CGFloat) -> CGFloat {
        let clamped = min(1.0, max(0.0, value))
        if clamped <= 0.0031308 {
            return clamped * 12.92
        }
        return 1.055 * pow(clamped, 1.0 / 2.4) - 0.055
    }

    return CGColor(red: gamma(linearR), green: gamma(linearG), blue: gamma(linearB), alpha: 1.0)
}

private let walletCardShineBaseLightness: CGFloat = 0.6320535732
private let walletCardShineBaseChroma: CGFloat = 0.2017874156
private let walletCardShineHue: CGFloat = 254.0879
private let walletCardEffectSteps: Int = 200

private func walletCardOverlayComposite(base: (CGFloat, CGFloat, CGFloat), blend: CGColor) -> CGColor {
    let components = blend.components ?? [0, 0, 0, 1]
    let blendChannels: [CGFloat] = components.count >= 3 ? [components[0], components[1], components[2]] : [components[0], components[0], components[0]]
    let baseChannels = [base.0, base.1, base.2]
    var result: [CGFloat] = []
    for index in 0 ..< 3 {
        let baseValue = baseChannels[index]
        let blendValue = blendChannels[index]
        if baseValue < 0.5 {
            result.append(2.0 * baseValue * blendValue)
        } else {
            result.append(1.0 - 2.0 * (1.0 - baseValue) * (1.0 - blendValue))
        }
    }
    return CGColor(red: result[0], green: result[1], blue: result[2], alpha: 1.0)
}

public let walletCardShineColorLUT: [CGColor] = {
    let cardBase: (CGFloat, CGFloat, CGFloat) = (0.0, 136.0 / 255.0, 1.0)
    var colors: [CGColor] = []
    colors.reserveCapacity(walletCardEffectSteps + 1)
    for index in 0 ... walletCardEffectSteps {
        let ty = CGFloat(index) / CGFloat(walletCardEffectSteps) * 2.0 - 1.0
        let shine = walletCardOklchColor(lightness: walletCardShineBaseLightness + 0.066 + ty * 0.1, chroma: walletCardShineBaseChroma * 0.8, hueDegrees: walletCardShineHue)
        colors.append(walletCardOverlayComposite(base: cardBase, blend: shine))
    }
    return colors
}()

private struct WalletCardMaskCacheKey: Hashable {
    public let pixelSide: Int
    public let backingScale: Int
    public let shineBlurRadius: Int
}

private struct WalletCardMaskImages {
    public let shine: CGImage
    public let stars: CGImage
}

private final class WalletCardMaskRenderer {
    public static let shared = WalletCardMaskRenderer()

    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let spokesKernel = CIColorKernel(source: """
        kernel vec4 walletCardSpokes(vec2 center, float spread) {
            vec2 delta = destCoord() - center;
            float position = atan(delta.y, delta.x) / 6.283185307179586;
            if (position < 0.0) {
                position += 1.0;
            }
            float first = max(0.0, 1.0 - abs(position - 0.25) / spread);
            float second = max(0.0, 1.0 - abs(position - 0.75) / spread);
            float alpha = max(first, second);
            return vec4(alpha, alpha, alpha, alpha);
        }
        """)
    private let lock = NSLock()
    private var cache: [WalletCardMaskCacheKey: WalletCardMaskImages] = [:]

    public func images(diameter: CGFloat, unit: CGFloat, backingScale: CGFloat) -> WalletCardMaskImages? {
        let effectiveBackingScale = min(2.0, backingScale)
        let pixelSide = max(8, Int(ceil(diameter * effectiveBackingScale)))
        let renderScale = CGFloat(pixelSide) / diameter
        let blurRadius = 10.0 * unit * renderScale
        let key = WalletCardMaskCacheKey(
            pixelSide: pixelSide,
            backingScale: Int(round(effectiveBackingScale * 1000.0)),
            shineBlurRadius: Int(round(blurRadius * 1000.0))
        )

        lock.lock()
        let cached = cache[key]
        lock.unlock()
        if let cached {
            return cached
        }

        guard let kernel = spokesKernel else {
            return nil
        }
        let extent = CGRect(x: 0.0, y: 0.0, width: CGFloat(pixelSide), height: CGFloat(pixelSide))
        let center = CIVector(x: extent.midX, y: extent.midY)
        guard let sharpShine = kernel.apply(extent: extent, arguments: [center, NSNumber(value: 0.11)]),
              let sharpStars = kernel.apply(extent: extent, arguments: [center, NSNumber(value: 0.16)]) else {
            return nil
        }

        let clampedShine = sharpShine.clampedToExtent()
        let blurredShine = clampedShine
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
            .cropped(to: extent)
        guard let shine = context.createCGImage(blurredShine, from: extent),
              let stars = context.createCGImage(sharpStars, from: extent) else {
            return nil
        }

        let result = WalletCardMaskImages(shine: shine, stars: stars)
        lock.lock()
        cache[key] = result
        lock.unlock()
        return result
    }
}

private func walletCardHash(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
    var px = x - floor(x / 289.0) * 289.0
    var py = y - floor(y / 289.0) * 289.0
    px = (px * 123.34).truncatingRemainder(dividingBy: 1.0)
    py = (py * 456.21).truncatingRemainder(dividingBy: 1.0)
    if px < 0 { px += 1 }
    if py < 0 { py += 1 }
    let d = px * (px + 45.32) + py * (py + 45.32)
    px += d
    py += d
    let value = (px * py).truncatingRemainder(dividingBy: 1.0)
    return value < 0 ? value + 1 : value
}

private func walletCardValueNoise(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
    let ix = floor(x)
    let iy = floor(y)
    let fx = x - ix
    let fy = y - iy
    let ux = fx * fx * (3.0 - 2.0 * fx)
    let uy = fy * fy * (3.0 - 2.0 * fy)
    let a = walletCardHash(ix, iy)
    let b = walletCardHash(ix + 1, iy)
    let c = walletCardHash(ix, iy + 1)
    let d = walletCardHash(ix + 1, iy + 1)
    let ab = a + (b - a) * ux
    let cd = c + (d - c) * ux
    return ab + (cd - ab) * uy
}

private func walletCardFbm(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
    var value: CGFloat = 0
    var amplitude: CGFloat = 0.5
    var px = x
    var py = y
    for _ in 0 ..< 4 {
        value += amplitude * walletCardValueNoise(px, py)
        px *= 2
        py *= 2
        amplitude *= 0.5
    }
    return value
}

public func walletCardTextureImage(size: NSSize, backingScale: CGFloat, baseColor: NSColor) -> CGImage? {
    let renderScale = min(2.0, backingScale)
    let width = max(1, Int(ceil(size.width * renderScale)))
    let height = max(1, Int(ceil(size.height * renderScale)))
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    let heightPx = CGFloat(height)

    let base = baseColor.usingColorSpace(.deviceRGB) ?? baseColor
    let baseChannels: [CGFloat] = [base.redComponent, base.greenComponent, base.blueComponent]

    func overlayBlend(_ baseValue: CGFloat, _ blendValue: CGFloat) -> CGFloat {
        if baseValue < 0.5 {
            return 2.0 * baseValue * blendValue
        }
        return 1.0 - 2.0 * (1.0 - baseValue) * (1.0 - blendValue)
    }

    for py in 0 ..< height {
        let flippedY = CGFloat(height - 1 - py)
        let uvY = flippedY / heightPx
        for px in 0 ..< width {
            let uvX = CGFloat(px) / heightPx
            let mottle = walletCardFbm(uvX * 244.5, uvY * 129.0) - 0.5
            let grain = walletCardValueNoise(CGFloat(px) * 1.7, flippedY * 1.7) - 0.5
            let value = min(1.0, max(0.0, 0.5 + mottle * 0.06 + grain * 0.03))
            let offset = py * bytesPerRow + px * 4
            pixels[offset] = 255
            pixels[offset + 1] = UInt8(min(1.0, max(0.0, overlayBlend(baseChannels[0], value))) * 255.0)
            pixels[offset + 2] = UInt8(min(1.0, max(0.0, overlayBlend(baseChannels[1], value))) * 255.0)
            pixels[offset + 3] = UInt8(min(1.0, max(0.0, overlayBlend(baseChannels[2], value))) * 255.0)
        }
    }
    guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
        return nil
    }
    return context.makeImage()
}

private final class WalletCardTextureRequest {
    private let lock = NSLock()
    private var value: Int = 0
    
    func set(_ value: Int) {
        lock.lock()
        self.value = value
        lock.unlock()
    }
    
    func get() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class WalletCardTextureCache {
    static let shared = WalletCardTextureCache()
    
    let queue = DispatchQueue(label: "WalletCardTextureCache", qos: .userInitiated)
    private let images: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 4
        return cache
    }()
    
    func cached(_ key: String) -> CGImage? {
        return images.object(forKey: key as NSString)
    }
    
    func store(_ image: CGImage, key: String) {
        images.setObject(image, forKey: key as NSString)
    }
}

public let walletCardStarPositions: [CGPoint] = [
    CGPoint(x: 14, y: 10), CGPoint(x: 70, y: 26), CGPoint(x: 126, y: 14), CGPoint(x: 188, y: 28), CGPoint(x: 248, y: 14),
    CGPoint(x: 22, y: 50), CGPoint(x: 120, y: 48), CGPoint(x: 212, y: 50), CGPoint(x: 262, y: 50), CGPoint(x: 222, y: 76),
    CGPoint(x: 56, y: 144), CGPoint(x: 110, y: 156), CGPoint(x: 156, y: 144), CGPoint(x: 188, y: 160), CGPoint(x: 156, y: 196), CGPoint(x: 188, y: 196)
]

public func walletCardStarHalfExtent(_ position: CGPoint) -> CGFloat {
    let seed = (position.x * 7.31 + position.y * 13.17).truncatingRemainder(dividingBy: 100.0) / 100.0
    return 3.0 + abs(seed)
}

public func walletCardSparklePath(halfExtent: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let waist = halfExtent * 0.18
    let outer: [CGPoint] = [
        CGPoint(x: 0, y: halfExtent), CGPoint(x: halfExtent, y: 0), CGPoint(x: 0, y: -halfExtent), CGPoint(x: -halfExtent, y: 0)
    ]
    let inner: [CGPoint] = [
        CGPoint(x: waist, y: waist), CGPoint(x: waist, y: -waist), CGPoint(x: -waist, y: -waist), CGPoint(x: -waist, y: waist)
    ]
    path.move(to: outer[0])
    for index in 0 ..< 4 {
        path.addLine(to: inner[index])
        path.addLine(to: outer[(index + 1) % 4])
    }
    path.closeSubpath()
    return path
}

private struct WalletCardEffectsGeometry: Equatable {
    public let bounds: CGRect
    public let unit: CGFloat
    public let backingScale: CGFloat
}

public final class WalletCardEffectsLayers {
    private let shineLayer = SimpleLayer()
    private let shineMaskLayer = SimpleLayer()
    private let textureLayer = SimpleLayer()
    private let starsLayer = SimpleLayer()
    private let starsMaskLayer = SimpleLayer()
    private var starShapeLayers: [CAShapeLayer] = []
    private let rimShadowLayer = CAShapeLayer()
    private let chipBaseLayer = CAGradientLayer()
    private let chipHighlightLayer = CAGradientLayer()

    private var appliedTilt = WalletCardTilt(tx: .greatestFiniteMagnitude, ty: .greatestFiniteMagnitude)
    private var appliedColorIndex: Int = -1
    private var textureKey: String = ""
    private var maskKey: WalletCardMaskCacheKey?
    private var geometry: WalletCardEffectsGeometry?
    private var unit: CGFloat = 1
    private var twinkleInstalled = true
    private var pendingTextureRenderKey: Int = 0
    private let latestTextureRequest = WalletCardTextureRequest()

    public init() {
        shineLayer.opacity = 0.75
        shineLayer.mask = shineMaskLayer
        shineMaskLayer.contentsGravity = .resize

        textureLayer.contentsGravity = .resize

        starsLayer.mask = starsMaskLayer
        starsMaskLayer.contentsGravity = .resize

        rimShadowLayer.fillRule = .evenOdd
        rimShadowLayer.fillColor = NSColor.black.cgColor
        rimShadowLayer.shadowColor = NSColor.black.cgColor
        rimShadowLayer.shadowOpacity = 0.16

        chipBaseLayer.colors = [NSColor(rgb: 0xe8e9ea).withAlphaComponent(0.88).cgColor, NSColor(rgb: 0xbbbdc0).withAlphaComponent(0.88).cgColor]
        setGradientAngle(chipBaseLayer, degrees: 127.28)
        chipHighlightLayer.colors = [
            NSColor.black.withAlphaComponent(0.08).cgColor,
            NSColor.white.withAlphaComponent(0.16).cgColor,
            NSColor.white.withAlphaComponent(0.48).cgColor,
            NSColor.white.withAlphaComponent(0.16).cgColor,
            NSColor.black.withAlphaComponent(0.08).cgColor
        ]
        setGradientAngle(chipHighlightLayer, degrees: 115)
        chipBaseLayer.borderColor = NSColor.black.withAlphaComponent(0.16).cgColor

        for position in walletCardStarPositions {
            let star = CAShapeLayer()
            star.fillColor = NSColor.white.withAlphaComponent(0.4).cgColor
            star.path = walletCardSparklePath(halfExtent: walletCardStarHalfExtent(position))
            starShapeLayers.append(star)
            starsLayer.addSublayer(star)
        }
    }

    private func setGradientAngle(_ layer: CAGradientLayer, degrees: CGFloat) {
        let radians = degrees * .pi / 180.0
        let dx = cos(radians) / 2.0
        let dy = sin(radians) / 2.0
        layer.startPoint = CGPoint(x: 0.5 - dx, y: 0.5 + dy)
        layer.endPoint = CGPoint(x: 0.5 + dx, y: 0.5 - dy)
    }

    public func install(into container: CALayer) {
        container.addSublayer(textureLayer)
        container.addSublayer(shineLayer)
        container.addSublayer(starsLayer)
        container.addSublayer(rimShadowLayer)
    }

    public func layout(bounds: CGRect, unit: CGFloat, safeZones: [CGRect], backingScale: CGFloat) {
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }
        self.unit = unit
        let geometry = WalletCardEffectsGeometry(bounds: bounds, unit: unit, backingScale: backingScale)
        let geometryChanged = geometry != self.geometry
        if geometryChanged {
            self.geometry = geometry
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if geometryChanged {
            textureLayer.frame = bounds

            let shineSide = 349.5 * unit
            let shineSize = CGSize(width: shineSide, height: shineSide)
            shineLayer.bounds = CGRect(origin: .zero, size: shineSize)
            shineLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            shineMaskLayer.frame = CGRect(origin: .zero, size: shineSize)
            shineMaskLayer.contentsScale = backingScale

            starsLayer.frame = bounds
            starsMaskLayer.bounds = CGRect(origin: .zero, size: shineSize)
            starsMaskLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            starsMaskLayer.contentsScale = backingScale

            installMasksIfNeeded(shineSide: shineSide, backingScale: backingScale)

            let rimPath = CGMutablePath()
            rimPath.addRect(bounds.insetBy(dx: -8.0 * unit, dy: -8.0 * unit))
            rimPath.addRoundedRect(in: bounds, cornerWidth: 20.0 * unit, cornerHeight: 20.0 * unit)
            rimShadowLayer.frame = bounds
            rimShadowLayer.path = rimPath
            rimShadowLayer.shadowRadius = 1.0 * unit
            let shadowAngle = 212.0 * CGFloat.pi / 180.0
            rimShadowLayer.shadowOffset = CGSize(width: -sin(shadowAngle) * unit, height: -cos(shadowAngle) * unit)
        }

        let inset = -8.0 * unit
        var visibleOrdinal = 0
        for (index, position) in walletCardStarPositions.enumerated() {
            let star = starShapeLayers[index]
            let point = CGPoint(x: position.x * unit, y: bounds.height - position.y * unit)
            star.position = point
            let starScale = unit
            var isHidden = false
            for zone in safeZones {
                if zone.insetBy(dx: inset, dy: inset).contains(point) {
                    isHidden = true
                    break
                }
            }
            star.isHidden = isHidden
            star.transform = CATransform3DMakeScale(starScale, starScale, 1)
            if !isHidden {
                installTwinkle(star, ordinal: visibleOrdinal)
                visibleOrdinal += 1
            } else {
                star.removeAnimation(forKey: "twinkle")
            }
        }

        CATransaction.commit()

        if geometryChanged {
            renderTextureIfNeeded(bounds: bounds, backingScale: backingScale)
            appliedTilt = WalletCardTilt(tx: .greatestFiniteMagnitude, ty: .greatestFiniteMagnitude)
        }
    }

    private func installMasksIfNeeded(shineSide: CGFloat, backingScale: CGFloat) {
        let effectiveBackingScale = min(2.0, backingScale)
        let pixelSide = max(8, Int(ceil(shineSide * effectiveBackingScale)))
        let renderScale = CGFloat(pixelSide) / shineSide
        let key = WalletCardMaskCacheKey(
            pixelSide: pixelSide,
            backingScale: Int(round(effectiveBackingScale * 1000.0)),
            shineBlurRadius: Int(round(10.0 * unit * renderScale * 1000.0))
        )
        guard key != maskKey else {
            return
        }
        guard let images = WalletCardMaskRenderer.shared.images(diameter: shineSide, unit: unit, backingScale: backingScale) else {
            return
        }
        shineMaskLayer.contents = images.shine
        starsMaskLayer.contents = images.stars
        maskKey = key
    }

    private func renderTextureIfNeeded(bounds: CGRect, backingScale: CGFloat) {
        let key = "\(Int(bounds.width))x\(Int(bounds.height))@\(backingScale)"
        guard key != textureKey else {
            return
        }
        textureKey = key
        pendingTextureRenderKey += 1
        let renderKey = pendingTextureRenderKey
        let textureSize = bounds.size

        let cache = WalletCardTextureCache.shared
        let renderScale = min(2.0, backingScale)
        let cacheKey = "\(max(1, Int(ceil(textureSize.width * renderScale))))x\(max(1, Int(ceil(textureSize.height * renderScale))))"
        let latestTextureRequest = self.latestTextureRequest
        latestTextureRequest.set(renderKey)
        if let texture = cache.cached(cacheKey) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.textureLayer.contents = texture
            CATransaction.commit()
            return
        }

        cache.queue.async { [weak self] in
            let texture: CGImage?
            if let cached = cache.cached(cacheKey) {
                texture = cached
            } else if latestTextureRequest.get() != renderKey {
                return
            } else {
                texture = walletCardTextureImage(size: textureSize, backingScale: backingScale, baseColor: NSColor(rgb: 0x0088ff))
                if let texture {
                    cache.store(texture, key: cacheKey)
                }
            }
            DispatchQueue.main.async {
                guard let self, self.pendingTextureRenderKey == renderKey else {
                    return
                }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.textureLayer.contents = texture
                CATransaction.commit()
            }
        }
    }

    private func installTwinkle(_ star: CAShapeLayer, ordinal: Int) {
        guard twinkleInstalled else {
            return
        }
        if star.animation(forKey: "twinkle") != nil {
            return
        }
        let n = CGFloat(ordinal)
        let rawDuration = 4.2 + (n * 0.41).truncatingRemainder(dividingBy: 1.0) * 2.6
        let duration = rawDuration * 0.5
        let delay = (n * 0.73).truncatingRemainder(dividingBy: duration)
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 0.92 * unit
        animation.toValue = 1.08 * unit
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.beginTime = CACurrentMediaTime() - Double(delay)
        star.add(animation, forKey: "twinkle")
    }

    public func setTwinkleEnabled(_ enabled: Bool) {
        twinkleInstalled = enabled
        if !enabled {
            for star in starShapeLayers {
                star.removeAnimation(forKey: "twinkle")
            }
        }
    }

    public func apply(tilt: WalletCardTilt) {
        guard tilt != appliedTilt else {
            return
        }
        appliedTilt = tilt

        let colorIndex = Int(round((tilt.ty + 1.0) * CGFloat(walletCardEffectSteps) / 2.0))
        let clampedColorIndex = max(0, min(walletCardEffectSteps, colorIndex))

        let angle = (-58.0 + tilt.tx * 60.0) * .pi / 180.0
        let shineTransform = CATransform3DConcat(CATransform3DMakeRotation(angle, 0, 0, 1), CATransform3DMakeScale(1, 1.65, 1))

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        shineLayer.transform = shineTransform
        if clampedColorIndex != appliedColorIndex {
            shineLayer.backgroundColor = walletCardShineColorLUT[clampedColorIndex]
            appliedColorIndex = clampedColorIndex
        }

        starsMaskLayer.transform = CATransform3DMakeRotation(angle, 0, 0, 1)

        CATransaction.commit()
    }
}
