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
import WalletContext
import GZIP

private let walletCollectibleLottieMaximumSize = 5 * 1024 * 1024

func walletCollectibleLottieData(_ data: Data) -> Data? {
    guard data.count <= walletCollectibleLottieMaximumSize else { return nil }
    let decoded: Data
    if data.starts(with: [0x1f, 0x8b]) {
        guard let unpacked = TGGUnzipData(data, UInt32(walletCollectibleLottieMaximumSize)) else { return nil }
        decoded = unpacked
    } else {
        decoded = data
    }
    guard decoded.count <= walletCollectibleLottieMaximumSize,
          (try? JSONSerialization.jsonObject(with: decoded)) is [String: Any] else { return nil }
    return decoded
}

func walletCollectibleNameAttributedString(_ name: String, font: NSFont) -> NSAttributedString {
    let string = NSMutableAttributedString(string: name)
    string.addAttribute(.font, value: font, range: NSMakeRange(0, string.length))
    string.addAttribute(.foregroundColor, value: theme.colors.text, range: NSMakeRange(0, string.length))
    if let numberRange = name.range(of: "#[0-9]+$", options: .regularExpression) {
        string.addAttribute(.foregroundColor, value: theme.colors.grayText, range: NSRange(numberRange, in: name))
    }
    return string
}

func walletCollectibleWebFile(_ file: WalletNftFile?) -> TelegramMediaWebFile? {
    guard let file else {
        return nil
    }
    return TelegramMediaWebFile(resource: file.resource, mimeType: file.mimeType, size: file.size, attributes: [])
}

@available(macOS 10.15, *)
final class WalletCollectibleRowItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    let environment: WalletUIEnvironment
    fileprivate let collectible: WalletContext.Collectible
    fileprivate let callback: (WalletContext.Collectible) -> Void
    fileprivate let nameLayout: TextViewLayout
    fileprivate let subtitleLayout: TextViewLayout
    fileprivate let image: TelegramMediaWebFile?

    @available(macOS 10.15, *)
    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, environment: WalletUIEnvironment, collectible: WalletContext.Collectible, viewType: GeneralViewType, callback: @escaping (WalletContext.Collectible) -> Void = { _ in }) {
        self.context = context
        self.environment = environment
        self.collectible = collectible
        self.callback = callback

        self.nameLayout = TextViewLayout(walletCollectibleNameAttributedString(collectible.name, font: .medium(.title)), maximumNumberOfLines: 1)
        self.subtitleLayout = TextViewLayout(.initialize(string: collectible.subtitle, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1)

        self.image = walletCollectibleWebFile(collectible.thumbnail)
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    override var height: CGFloat {
        return 58
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        let textWidth = blockWidth - viewType.innerInset.left - 40 - 10 - 20 - viewType.innerInset.right
        nameLayout.measure(width: textWidth)
        subtitleLayout.measure(width: textWidth)
        return true
    }

    override func viewClass() -> AnyClass {
        return WalletCollectibleRowView.self
    }
}

@available(macOS 10.15, *)
private final class WalletCollectibleRowView: GeneralContainableRowView {
    private let placeholderView = View(frame: NSMakeRect(0, 0, 40, 40))
    private let imageView = TransformImageView(frame: NSMakeRect(0, 0, 40, 40))
    private let nameView = TextView()
    private let subtitleView = TextView()
    private let nextView = ImageView()
    private let imageFetchDisposable = MetaDisposable()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        placeholderView.layer?.cornerRadius = 12

        for textView in [nameView, subtitleView] {
            textView.userInteractionEnabled = false
            textView.isSelectable = false
        }

        addSubview(placeholderView)
        addSubview(imageView)
        addSubview(nameView)
        addSubview(subtitleView)
        addSubview(nextView)

        containerView.set(handler: { [weak self] _ in
            guard let item = self?.item as? WalletCollectibleRowItem else {
                return
            }
            item.callback(item.collectible)
        }, for: .Click)
    }

    deinit {
        imageFetchDisposable.dispose()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateColors() {
        super.updateColors()
        placeholderView.backgroundColor = theme.colors.grayForeground
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? WalletCollectibleRowItem else {
            return
        }

        nameView.update(item.nameLayout)
        subtitleView.update(item.subtitleLayout)
        nextView.image = theme.icons.generalNext
        nextView.sizeToFit()

        if let image = item.image {
            imageView.isHidden = false
            imageView.setSignal(item.environment.webFilePhoto( photo: image, scale: backingScaleFactor))
            imageFetchDisposable.set(fetchedMediaResource(mediaBox: item.context.account.postbox.mediaBox, userLocation: .other, userContentType: .other, reference: MediaResourceReference.standalone(resource: image.resource)).start())
            imageView.set(arguments: TransformImageArguments(corners: ImageCorners(radius: 12), imageSize: NSMakeSize(40, 40), boundingSize: NSMakeSize(40, 40), intrinsicInsets: NSEdgeInsetsZero))
        } else {
            imageView.isHidden = true
            imageFetchDisposable.set(nil)
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()

        guard let item = item as? WalletCollectibleRowItem else {
            return
        }

        let leftInset = item.viewType.innerInset.left
        let rightInset = item.viewType.innerInset.right

        placeholderView.centerY(x: leftInset)
        imageView.frame = placeholderView.frame

        nextView.centerY(x: containerView.frame.width - rightInset - nextView.frame.width)

        let textX = leftInset + 40 + 10
        let textHeight = nameView.frame.height + 2 + subtitleView.frame.height
        let textY = floorToScreenPixels(backingScaleFactor, (containerView.frame.height - textHeight) / 2)
        nameView.setFrameOrigin(NSMakePoint(textX, textY))
        subtitleView.setFrameOrigin(NSMakePoint(textX, nameView.frame.maxY + 2))
    }

    override var additionBorderInset: CGFloat {
        return 40 + 10
    }
}
