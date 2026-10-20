import Cocoa
import Foundation
import TGUIKit
import UniqueGiftBackground
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import TelegramMediaUtils
import TelegramMedia
import LocalAnimations
import CurrencyFormat
import PremiumStatusUI
import SceneEffects
import DustLayer
import InAppPurchaseManager
import ObjcUtils
import PremiumUI
import CalendarUtils
import DateUtils
import LokiRng
import FoundationUtils
import InputView
import InputTextView
import InlineStickerLayer



extension StarGift.UniqueGift.Attribute {
    public var file: TelegramMediaFile? {
        switch self {
        case .backdrop:
            return nil
        case let .model(_, file, _, _):
            return file
        case let .pattern(_, file, _):
            return file
        case .originalInfo:
            return nil
        }
    }
    public var rarity: Rarity {
        switch self {
        case let .backdrop(_, _, _, _, _, _, rarity):
            return rarity
        case let .model(_, _, rarity, _):
            return rarity
        case let .pattern(_, _, rarity):
            return rarity
        case .originalInfo:
            return .permille(0)
        }
    }
    public var name: String {
        switch self {
        case let .backdrop(name, _, _, _, _, _, _):
            return name
        case let .model(name, _, _, _):
            return name
        case let .pattern(name, _, _):
            return name
        case .originalInfo:
            return ""
        }
    }
}

private final class AttrRowItem: GeneralRowItem {
    fileprivate let entry: GridController.Entry
    fileprivate let arguments: Arguments
    fileprivate let model: TelegramMediaFile
    public init(_ initialSize: NSSize, stableId: AnyHashable, entry: GridController.Entry, arguments: Arguments, model: TelegramMediaFile) {
        self.entry = entry
        self.arguments = arguments
        self.model = model
        super.init(initialSize, height: 110, stableId: stableId)
    }
    
    public override func viewClass() -> AnyClass {
        return AttrRowItemView.self
    }
}

private final class AttrRowItemView : GeneralRowView {
    private final class OptionView: Control {
        private var selectionView: View?
        private let modelView: NSView = StarsHooks.shared.makeStickerView(NSMakeRect(0, 0, 60, 60))
        private let rarityTextView = TextView()
        private let nameView = TextView()
        private var backgroundView: UniqueGiftBackgroundView?
        private var backgroundContent: UniqueGiftBackgroundContent?
        private var backgroundContext: (any AccountContextProtocol)?
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(modelView)
            addSubview(rarityTextView)
            addSubview(nameView)
            nameView.userInteractionEnabled = false
            nameView.isSelectable = false
            
            rarityTextView.userInteractionEnabled = false
            rarityTextView.isSelectable = false

            
            (modelView as? View)?.userInteractionEnabled = false
            background = theme.colors.background
            layer?.cornerRadius = 14
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func set(entry: GridController.Entry, model:TelegramMediaFile, attr: StarGift.UniqueGift.Attribute, mode: StarGift_Builder_Section, selected: Bool, arguments: Arguments, animated: Bool) {
            
            setSingle(handler: { [weak arguments] _ in
                arguments?.selectAttribute(attr, mode)
            }, for: .Click)
            
            let file = attr.file ?? model
            
            var modelColors: [LottieColor] = []
            if mode == .symbols {
                modelColors = [.init(keyPath: "", color: NSColor(0xffffff))]
            }
            
            
            
            (modelView as? StarsStickerView)?.updateStarsSticker(file: file, size: modelView.frame.size, context: arguments.context, colors: modelColors, playback: .loopHidden, animated: animated)
            modelView.centerX(y: 15)
            
            let nameLayout = TextViewLayout(.initialize(string: attr.name, color: mode == .models ? theme.colors.text : .white, font: .normal(.short)), truncationType: .middle, alignment: .center)
            nameLayout.measure(width: frame.width - 10)
            nameView.update(nameLayout)
            
            nameView.centerX(y: frame.height - 5 - nameView.frame.height - 3)
            
            
            let badgeColor = attr.rarity.badgeColor ?? (mode == .models ? theme.colors.grayIcon : .white)
            let rarityLayout = TextViewLayout(.initialize(string: attr.rarity.badgeText, color: badgeColor, font: .medium(9)), alignment: .center)
            rarityLayout.measure(width: .greatestFiniteMagnitude)

            rarityTextView.update(rarityLayout)
            rarityTextView.setFrameSize(NSMakeSize(rarityTextView.frame.width + 6, rarityTextView.frame.height + 5))

            rarityTextView.layer?.cornerRadius = rarityTextView.frame.height / 2
            rarityTextView.backgroundColor = badgeColor.withAlphaComponent(0.2)
            
            rarityTextView.setFrameOrigin(NSMakePoint(frame.width - rarityTextView.frame.width - 5, 5))
            
            if selected {
                let current: View
                var isNew: Bool = false
                if let selectionView {
                    current = selectionView
                } else {
                    current = View(frame: bounds.insetBy(dx: 2, dy: 2))
                    self.selectionView = current
                    addSubview(current)
                    current.layer?.cornerRadius = 12
                    current.layer?.borderWidth = 1.5
                    isNew = true
                }
                if isNew, animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
                current.layer?.borderColor = mode == .models ? theme.colors.accent.cgColor : .white
            } else if let selectionView {
                performSubviewRemoval(selectionView, animated: animated)
                self.selectionView = nil
            }
            
            switch mode {
            case .backdrops, .symbols:
                let backdropAttr = mode == .symbols ? entry.effectiveBackdrop : attr
                let symbolAttr = mode == .backdrops ? entry.effectiveSymbol : attr
                if let content = UniqueGiftBackgroundContent(attributes: [backdropAttr, symbolAttr].compactMap { $0 }) {
                    if self.backgroundView == nil {
                        let current = UniqueGiftBackgroundView(frame: bounds)
                        self.addSubview(current, positioned: .below, relativeTo: modelView)
                        self.backgroundView = current
                    }
                    self.backgroundContent = content
                    self.backgroundContext = arguments.context
                    self.updateBackground()
                } else {
                    backgroundView?.removeFromSuperview()
                    self.backgroundView = nil
                    self.backgroundContent = nil
                    self.backgroundContext = nil
                }
            default:
                backgroundView?.removeFromSuperview()
                self.backgroundView = nil
                self.backgroundContent = nil
                self.backgroundContext = nil
            }
        }

        override func layout() {
            super.layout()
            self.updateBackground()
        }

        private func updateBackground() {
            guard let backgroundView, let content = backgroundContent, let context = backgroundContext else {
                return
            }
            backgroundView.frame = bounds
            backgroundView.update(context: context, content: content, style: .item(giftCenterY: modelView.frame.midY, cornerRadius: 14))
        }
    }
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? AttrRowItem else {
            return
        }
        
        let itemSize: NSSize
        let count = 3
        let space = frame.width - (10 * CGFloat(count - 1))
        itemSize = NSMakeSize(floor(space / CGFloat(count)), frame.height - 10)
        
        while self.subviews.count > item.entry.attributes.count {
            self.subviews.last?.removeFromSuperview()
        }
        while self.subviews.count < item.entry.attributes.count {
            self.addSubview(OptionView(frame: itemSize.bounds))
        }
        
        layout()
        
        for (i, subview) in subviews.enumerated() {
            let view = subview as? OptionView
            view?.set(entry: item.entry, model: item.model, attr: item.entry.attributes[i], mode: item.entry.mode, selected: item.entry.selected == item.entry.attributes[i], arguments: item.arguments, animated: animated)
        }
        var x: CGFloat = 0

        for (_, subview) in subviews.enumerated() {
            let view = subview as? OptionView
            view?.setFrameSize(itemSize)
            subview.setFrameOrigin(x, 5)
            x += subview.frame.width + 10
        }
    }
}

public enum StarGift_Builder_Section : Int {
    case models = 0
    case backdrops = 1
    case symbols = 2
}

private final class GridController : ViewController {
    
    public struct Entry : Comparable, Identifiable {
        public static func < (lhs: GridController.Entry, rhs: GridController.Entry) -> Bool {
            return lhs.index < rhs.index
        }
        public var mode: StarGift_Builder_Section
        public var attributes: [StarGift.UniqueGift.Attribute]
        public var selected: StarGift.UniqueGift.Attribute?
        
        public var effectiveBackdrop: StarGift.UniqueGift.Attribute?
        public var effectiveSymbol: StarGift.UniqueGift.Attribute?

        
        public var model: TelegramMediaFile
        public var index: Int32
        public var stableId: AnyHashable {
            return index
        }
        public init(mode: StarGift_Builder_Section, attributes: [StarGift.UniqueGift.Attribute], selected: StarGift.UniqueGift.Attribute? = nil, effectiveBackdrop: StarGift.UniqueGift.Attribute? = nil, effectiveSymbol: StarGift.UniqueGift.Attribute? = nil, model: TelegramMediaFile, index: Int32) {
            self.mode = mode
            self.attributes = attributes
            self.selected = selected
            self.effectiveBackdrop = effectiveBackdrop
            self.effectiveSymbol = effectiveSymbol
            self.model = model
            self.index = index
        }
    }
    
 
    fileprivate let mode: StarGift_Builder_Section
    fileprivate let tableView: TableView = TableView()
    private let maskLayer = SimpleGradientLayer()
    
    private var entries: [Entry] = []
    
    public init(mode: StarGift_Builder_Section) {
        self.mode = mode
        super.init()
    }
    
    public override func viewDidResized(_ size: NSSize) {
        super.viewDidResized(size)
        tableView.frame = bounds
    }
    
    public func set(model: TelegramMediaFile, attrs: [StarGift.UniqueGift.Attribute], selected: StarGift.UniqueGift.Attribute?, arguments: Arguments, state: State, animated: Bool) {
        let chunks = attrs.chunks(3)
        var index: Int32 = 0
        
        
        var entries: [Entry] = []
        for chunk in chunks {
            entries.append(.init(mode: self.mode, attributes: chunk, selected: selected, effectiveBackdrop: state.selectedBackdrop ?? state.firstBackdrop, effectiveSymbol: state.selectedSymbol ?? state.firstSymbol, model: model, index: index))
            index += 1
        }
        let size = frame.size
        
        let (deleted,inserted,updated) = proccessEntriesWithoutReverse(self.entries, right: entries, { entry -> TableRowItem in
            return AttrRowItem(size, stableId: entry.stableId, entry: entry, arguments: arguments, model: model)
        })
        
        let transition = TableUpdateTransition(deleted: deleted, inserted: inserted, updated: updated, animated: animated, state: .none(nil), grouping: true, animateVisibleOnly: true, searchState: nil)

        self.tableView.merge(with: transition)
        
        self.entries = entries
        
    }
    public override var supportSwipes: Bool {
        return true
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.getBackgroundColor = {
            theme.colors.listBackground
        }
        
        guard let clipView = tableView.layer else { return }
        
        let gradientHeight: CGFloat = 10
        let h = clipView.bounds.height

        
        maskLayer.frame = clipView.bounds
        maskLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.black.cgColor,
            NSColor.black.cgColor,
            NSColor.black.cgColor
        ]

        maskLayer.locations = [
            0.0,
            NSNumber(value: Float(gradientHeight / h)),
            NSNumber(value: Float((h - gradientHeight) / h)),
            1.0
        ]

        maskLayer.startPoint = CGPoint(x: 0.5, y: 0)
        maskLayer.endPoint = CGPoint(x: 0.5, y: 1)

        clipView.mask = maskLayer
        
        tableView.contentInsets = NSEdgeInsets(top: 5, left: 0, bottom: 20, right: 0)
        tableView.frame = bounds
        addSubview(tableView)
        
        backgroundColor = .clear
        
        readyOnce()
        
    }
}

private final class GridRowItem : GeneralRowItem {
    fileprivate let state: State
    fileprivate let arguments: Arguments
    public init(_ initialSize: NSSize, stableId: AnyHashable, state: State, arguments: Arguments) {
        self.state = state
        self.arguments = arguments
        super.init(initialSize, height: 260, stableId: stableId)
    }
    
    public override func viewClass() -> AnyClass {
        return GridRowItemView.self
    }
}

private final class GridRowItemView : GeneralRowView {
    public let controller: SectionViewController
    public required init(frame frameRect: NSRect) {
        controller = .init(sections: [
            .init(title: { return "" }, controller: GridController(mode: .models)),
            .init(title: { "" }, controller: GridController(mode: .backdrops)),
            .init(title: { "" }, controller: GridController(mode: .symbols))
        ], selected: 0, hasBar: false)
        
        controller._frameRect = NSMakeRect(20, 0, frameRect.width - 40, frameRect.height)

//        tableView = TableView(frame: NSMakeRect(0, 0, frameRect.width - 40, frameRect.height))
        super.init(frame: frameRect)
//        addSubview(tableView)
        addSubview(controller.view)
        
        controller.genericView._backgroundColor = theme.colors.listBackground
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        controller.view.frame = NSMakeRect(20, 0, frame.width - 40, frame.height)
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? GridRowItem else {
            return
        }
        
        
        let models = controller.sections[StarGift_Builder_Section.models.rawValue].controller as? GridController
        let backdrops = controller.sections[StarGift_Builder_Section.backdrops.rawValue].controller as? GridController
        let symbols = controller.sections[StarGift_Builder_Section.symbols.rawValue].controller as? GridController
        
        let modelAttr = item.state.selectedModel ?? item.state.attributes.filter({ $0.attributeType == .model }).first
        
        
        var modelFile: TelegramMediaFile?
        switch modelAttr {
        case .model(_, let file, _, _):
            modelFile = file
        default:
            break
        }
        
        guard let modelFile else {
            return
        }
        
        
        models?.set(model: modelFile, attrs: item.state.filteredModels, selected: item.state.selectedModel, arguments: item.arguments, state: item.state, animated: animated)
        backdrops?.set(model: modelFile, attrs: item.state.attributes.filter({ $0.attributeType == .backdrop }), selected: item.state.selectedBackdrop, arguments: item.arguments, state: item.state, animated: animated)
        symbols?.set(model: modelFile, attrs: item.state.attributes.filter({ $0.attributeType == .pattern }), selected: item.state.selectedSymbol, arguments: item.arguments, state: item.state, animated: animated)

        controller.select(Int(item.state.selected.rawValue), animated)
        
    }
}

private final class SegmentRowItem: GeneralRowItem {
    fileprivate let arguments: Arguments
    fileprivate let state: State
    public init(_ initialSize: NSSize, stableId: AnyHashable, state: State, arguments: Arguments) {
        self.arguments = arguments
        self.state = state
        super.init(initialSize, height: 40, stableId: stableId)
    }
    
    public override func viewClass() -> AnyClass {
        return SegmentRowView.self
    }
}

private final class SegmentRowView : GeneralRowView {
    fileprivate let segmentControl: CatalinaStyledSegmentController
    public required init(frame frameRect: NSRect) {
        segmentControl = CatalinaStyledSegmentController(frame: NSMakeRect(0, 0, frameRect.width - 40, 30))
        super.init(frame: frameRect)
        addSubview(segmentControl.view)
        
        segmentControl.theme = CatalinaSegmentTheme(backgroundColor: theme.colors.listBackground, foregroundColor: theme.colors.background, activeTextColor: theme.colors.text, inactiveTextColor: theme.colors.listGrayText)
        
        segmentControl.set(items: [
            CatalinaSegmentedItem(
                title: strings().starGiftModelBuilderModels,
                handler: { [weak self] in
                    if let item = self?.item as? SegmentRowItem {
                        item.arguments.toggleSection(.models)
                    }
                }
            ),
            CatalinaSegmentedItem(
                title: strings().starGiftModelBuilderBackdrops,
                handler: { [weak self] in
                    if let item = self?.item as? SegmentRowItem {
                        item.arguments.toggleSection(.backdrops)
                    }
                }
            ),
            CatalinaSegmentedItem(
                title: strings().starGiftModelBuilderSymbols,
                handler: { [weak self] in
                    if let item = self?.item as? SegmentRowItem {
                        item.arguments.toggleSection(.symbols)
                    }
                }
            )
        ])

    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? SegmentRowItem else {
            return
        }
        
        segmentControl.set(selected: item.state.selected.rawValue)
    }
    
    public override func layout() {
        super.layout()
        segmentControl.view.center()
    }
}


private final class HeaderItem : GeneralRowItem {
    
    
    public class ActionItem {
        public var context: (any AccountContextProtocol)
        public var title: TextViewLayout
        public var subtext: TextViewLayout
        public var action:()->Void
        public var size: NSSize = .zero
        public let rarity: StarGift.UniqueGift.Attribute.Rarity

        public init(context: (any AccountContextProtocol), rarity: StarGift.UniqueGift.Attribute.Rarity, title: String, subtext: String, action: @escaping () -> Void) {
            self.context = context

            self.title = .init(.initialize(string: title, color: NSColor.white.withAlphaComponent(0.8), font: .medium(.text)), maximumNumberOfLines: 1)
            self.subtext = .init(.initialize(string: subtext, color: NSColor.white.withAlphaComponent(0.4), font: .normal(.small)), maximumNumberOfLines: 1)
            self.action = action
            self.rarity = rarity
        }
        
        public func measure(width: CGFloat) {
            self.title.measure(width: width - 10)
            self.subtext.measure(width: width - 10)

            self.size = NSMakeSize(width, 5 + title.layoutSize.height + 5 + subtext.layoutSize.height + 5)
        }
    }
    
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let title: TextViewLayout
    fileprivate let info: TextViewLayout
    fileprivate let arguments:Arguments
    fileprivate let attributes: [StarGift.UniqueGift.Attribute]
    
    fileprivate var patterns:[(String, TelegramMediaFile)] = []
    fileprivate var backdrops:[(String, StarGift.UniqueGift.Attribute)] = []
    fileprivate var models:[(String, StarGift.UniqueGift.Attribute)] = []

    private var patternIndex: Int = 0
    private var backdropIndex: Int = 0
    private var modelIndex: Int = 0
    
    
    public let uniqueGift: StarGift.UniqueGift?
    public let state: State
    
    public var actions: [ActionItem] = []
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), arguments: Arguments, state: State, attributes: [StarGift.UniqueGift.Attribute]) {
        self.arguments = arguments
        self.context = context
        self.attributes = attributes
        self.state = state
        
        self.uniqueGift = state.gift.unique
        
        self.patterns = attributes.compactMap { attribute in
            switch attribute {
            case let .pattern(name, file, _):
                return (name, file)
            default:
                return nil
            }
        }
        
        self.backdrops = attributes.compactMap { attribute in
            switch attribute {
            case let .backdrop(name, _, _, _, _, _, _):
                return (name, attribute)
            default:
                return nil
            }
        }
        
        self.models = attributes.compactMap { attribute in
            switch attribute {
            case let .model(name, _, _, _):
                return (name, attribute)
            default:
                return nil
            }
        }
        
        self.title = .init(.initialize(string: state.gift.title, color: .white, font: .medium(18)))
        self.info = .init(.initialize(string: state.mode == .random ? "Random Traits" : "Selected Traits", color: NSColor.white.withAlphaComponent(0.8), font: .normal(.text)), alignment: .center)
        
       

        for (_, model) in models {
            switch model {
            case let .model(_, file, _, _):
                _ = freeMediaFileInteractiveFetched(context: context, fileReference: .standalone(media: file)).start()
            default:
                break
            }
        }
        
        if let pattern = state.selectedSymbol {
            patternIndex = patterns.firstIndex(where: { $0.1.fileId == pattern.file?.fileId }) ?? 0
        } else {
            patternIndex = 0
        }
        if let backdrop = state.selectedBackdrop {
            backdropIndex = backdrops.firstIndex(where: { $0.1 == backdrop }) ?? 0
        } else {
            backdropIndex = 0
        }
        if let model = state.selectedModel {
            modelIndex = models.firstIndex(where: { $0.1 == model }) ?? 0
        } else {
            modelIndex = 0
        }
        
        super.init(initialSize, stableId: stableId)
        
        makeNextPattern()
    }
    
    public func makeNextPattern() {
        
        actions = [.init(context: context, rarity: models[modelIndex].1.rarity, title: models[modelIndex].0, subtext: strings().starGiftModelBuilderSubtextModel, action: { [weak self] in
            self?.arguments.toggleSection(.models)
        }), .init(context: context, rarity: backdrops[backdropIndex].1.rarity, title: backdrops[backdropIndex].0, subtext: strings().starGiftModelBuilderSubtextBackdrop, action: { [weak self] in
            self?.arguments.toggleSection(.backdrops)
        }), .init(context: context, rarity: state.selectedSymbol?.rarity ?? .permille(0), title: patterns[patternIndex].0, subtext: strings().starGiftModelBuilderSubtextSymbol, action: { [weak self] in
            self?.arguments.toggleSection(.symbols)
        })]
        
        let _ = self.makeSize(initialSize.width)
        
        self.redraw(animated: true)
    }
    
    public var model: TelegramMediaFile {
        switch self.models[self.modelIndex].1 {
        case let .model(_, file, _, _):
            return file
        default:
            fatalError()
        }
    }
    public var pattern: TelegramMediaFile {
        return self.patterns[self.patternIndex].1
    }
    
    public var patternColor: NSColor {
        let value = self.backdrops[self.backdropIndex].1
        switch value {
        case let .backdrop(_, _, _, _, patternColor, _, _):
            return NSColor(UInt32(bitPattern: patternColor))
        default:
            fatalError()
        }
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        self.title.measure(width: width - 40)
        self.info.measure(width: width - 40)
        
        
        for action in actions {
            action.measure(width: 120)
        }
        

        return true
    }
    
    public override var height: CGFloat {
        var height: CGFloat = 0
        
        height += 30
        height += 100
        height += 20
        
        height += title.layoutSize.height
        height += 5
        height += 20//info.layoutSize.height
        height += 10
        
        if !actions.isEmpty {
            height += 70
        }
        
        return height
    }
    
    public override func viewClass() -> AnyClass {
        return HeaderView.self
    }
    
    public var backgroundContent: UniqueGiftBackgroundContent? {
        switch self.backdrops[self.backdropIndex].1 {
        case let .backdrop(_, _, inner, outer, patternColor, _, _):
            return UniqueGiftBackgroundContent(colors: UniqueGiftColors(center: inner, edge: outer, pattern: patternColor), pattern: .file(self.pattern))
        default:
            return nil
        }
    }
}

private final class HeaderView : GeneralRowView {
    private let textView = TextView()
    private let infoView = TextView()
    private let dismiss = ImageButton()
    private let giftView = StarsHooks.shared.makeStickerView(NSMakeRect(0, 0, 100, 100))
    private let backgroundView = UniqueGiftBackgroundView(frame: .zero)
    
    
    private var ownerActions: View?
    
    public class ActionView : Control {
        private let textView: InteractiveTextView = InteractiveTextView()
        private let subtextView = TextView()
        private let rarityTextView = TextView()
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            textView.userInteractionEnabled = false
            textView.textView.isSelectable = false
            
            subtextView.userInteractionEnabled = false
            subtextView.isSelectable = false
            
            addSubview(textView)
            addSubview(subtextView)
            addSubview(rarityTextView)
            
            rarityTextView.userInteractionEnabled = false
            rarityTextView.isSelectable = false
            
            layer?.masksToBounds = false

        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func set(item: HeaderItem.ActionItem) {
            self.textView.set(text: item.title, context: item.context)
            self.subtextView.update(item.subtext)
            
            layer?.masksToBounds = false
            
            let rarityLayout = TextViewLayout(.initialize(string: item.rarity.badgeText, color: NSColor.white, font: .medium(9)), alignment: .center)
            rarityLayout.measure(width: .greatestFiniteMagnitude)

            rarityTextView.update(rarityLayout)
            rarityTextView.setFrameSize(NSMakeSize(rarityTextView.frame.width + 6, rarityTextView.frame.height + 5))

            rarityTextView.layer?.cornerRadius = rarityTextView.frame.height / 2
            rarityTextView.backgroundColor = NSColor.white.withAlphaComponent(0.5)
            rarityTextView.layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
            rarityTextView.layer?.borderWidth = 1.0
            
            setSingle(handler: { [weak item] _ in
                item?.action()
            }, for: .Click)
            
            needsLayout = true
        }
        
        public override func layout() {
            super.layout()
            textView.centerX(y: 5)
            subtextView.centerX(y: textView.frame.maxY + 5)
            
            rarityTextView.setFrameOrigin(NSMakePoint(frame.width - rarityTextView.frame.width + 2, -rarityTextView.frame.height/2))
        }
    }
    
    public final class RandomizeView : Control {
        public enum Mode {
            case full
            case short
        }
        private var textView: TextView?
        private let imageView = ImageView()
        private var mode: Mode = .short
        private var controllerMode: State.Mode = .random
        private var state: State?
        private var timer: SwiftSignalKit.Timer?
        
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(imageView)
            scaleOnClick = true
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func update(state: State, animated: Bool) {
            
            let previousControllerMode = self.controllerMode
            self.controllerMode = state.mode
            self.state = state
            
            guard let superview else {
                return
            }
            switch state.mode {
            case .custom:
                imageView.image = TelegramThemeHooks.shared.image(.iconVideoPlayerPlay).precomposed(.white)
            case .random:
                imageView.image = TelegramThemeHooks.shared.image(.iconVideoPlayerPause).precomposed(.white)
            }
            imageView.contentGravity = .resizeAspectFill
            imageView.setFrameSize(NSMakeSize(12, 12))
            imageView.animates = true

            var size = NSMakeSize(24, 24)
            
            if previousControllerMode != state.mode {
                
                self.mode = .full
                
                let string: String
                switch state.mode {
                case .custom:
                    string = strings().starGiftModelBuilderSelectedTraits
                case .random:
                    string = strings().starGiftModelBuilderRandomizeTraits
                }
                let layout: TextViewLayout = TextViewLayout(.initialize(string: string, color: .white, font: .medium(.text)))
                layout.measure(width: .greatestFiniteMagnitude)
                
                
                let current: TextView
                let isNew: Bool
                if let view = self.textView {
                    current = view
                    isNew = false
                } else {
                    current = TextView()
                    current.userInteractionEnabled = false
                    current.isSelectable = false
                    current.isEventLess = true
                    self.textView = current
                    self.addSubview(current)
                    isNew = true
                }
                current.update(layout)
                current.centerY(x: 5)
                
                if isNew {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
                
                timer = .init(timeout: 5.0, repeat: false, completion: { [weak self] in
                    if let view = self?.textView, let state = self?.state {
                        self?.mode = .short
                        performSubviewRemoval(view, animated: true)
                        self?.textView = nil
                        self?.update(state: state, animated: true)
                    }
                }, queue: .mainQueue())
                
                timer?.start()
            }
            
            if let textView {
                size = NSMakeSize(5 + textView.frame.width + 5 + imageView.frame.width + 5, 24)
            }
            
            
            layer?.cornerRadius = size.height / 2
            
            backgroundColor = NSColor.white.withAlphaComponent(0.6)
            layer?.borderColor = NSColor.white.withAlphaComponent(0.8).cgColor
            layer?.borderWidth = 1.0
            
            let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate
            
            transition.updateFrame(view: self, frame: CGRect(origin: NSMakePoint(superview.frame.width - size.width - 14, 14), size: size))
            
            self.controllerMode = state.mode
            
            self.updateLayout(size: size, transition: transition)
            
        }
        
        public override func layout() {
            super.layout()
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
        
        public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            if let textView {
                transition.updateFrame(view: textView, frame: textView.centerFrameY(x: 5))
                transition.updateFrame(view: imageView, frame: imageView.centerFrameY(x: size.width - imageView.frame.width - 5))
            } else {
                transition.updateFrame(view: imageView, frame: imageView.centerFrame())
            }
        }
    }
    
    private let playView: RandomizeView = RandomizeView(frame: .zero)
    
    private var timer: SwiftSignalKit.Timer?
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backgroundView)
        addSubview(giftView)
        addSubview(textView)
        addSubview(infoView)
        addSubview(dismiss)
        addSubview(playView)
        
        infoView.isSelectable = false
        
        (giftView as? Control)?.scaleOnClick = true
        (giftView as? Control)?.tooltipOnclick = true

    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? HeaderItem else {
            return
        }
        
        playView.setSingle(handler: { [weak item] _ in
            item?.arguments.toggleMode()
        }, for: .Click)
        
        dismiss.set(image: TelegramThemeHooks.shared.image(.iconPipClose).precomposed(.white), for: .Normal)
        dismiss.setGlassEffect(size: NSMakeSize(36, 36))
        dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        dismiss.scaleOnClick = true
        
        dismiss.setSingle(handler: { [weak item] _ in
            item?.arguments.dismiss()
        }, for: .Click)
        
        let update:()->Void = { [weak self] in
            guard let self else {
                return
            }
            self.updateBackground(animated: animated)
            (self.giftView as? StarsStickerView)?.updateStarsSticker(file: item.model, size: giftView.frame.size, context: item.context, colors: [], playback: .standard, animated: animated)
        }
        
        self.timer = .init(timeout: 2.5, repeat: true, completion: { [weak item] in
            item?.arguments.makeNextPattern()
        }, queue: .mainQueue())
        
        self.timer?.start()
        update()
        
        if !item.actions.isEmpty {
            
            let current: View
            if let view = ownerActions {
                current = view
            } else {
                current = View()
                current.layer?.masksToBounds = false
                addSubview(current)
                self.ownerActions = current
            }
            
            while current.subviews.count > item.actions.count {
                current.subviews.removeLast()
            }
            
            while current.subviews.count < item.actions.count {
                current.addSubview(ActionView(frame: .zero))
            }
            
            for (i, action) in item.actions.enumerated() {
                let view = current.subviews[i] as! ActionView
                view.layer?.cornerRadius = 10
                view.scaleOnClick = true
                
                let textColor = item.uniqueGift?.backdrop?.first?.lightness ?? 1.0 > 0.8 ? NSColor(0x000000) : NSColor(0xffffff)

                view.background = textColor.withAlphaComponent(0.2)
                view.set(item: action)
            }
            
        } else if let view = ownerActions {
            performSubviewRemoval(view, animated: animated)
            self.ownerActions = nil
        }
        
        textView.update(item.title)
        infoView.update(item.info)
                
        
        playView.update(state: item.state, animated: animated)

        //let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate
        
        //updateLayout(size: frame.size, transition: transition)
    }
    
    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        
        if let ownerActions {
            ownerActions.setFrameSize(NSMakeSize(size.width, 44))
            ownerActions.centerX(y: size.height - ownerActions.frame.height - 10)
            
            infoView.centerX(y: ownerActions.frame.minY - 20 - 15)

                        
            let itemSize = (frame.width - (CGFloat(ownerActions.subviews.count + 1) * 10)) / CGFloat(ownerActions.subviews.count)
            var x: CGFloat = 10
            for subview in ownerActions.subviews {
                subview.frame = NSMakeRect(x, 0, itemSize, ownerActions.frame.height)
                x += subview.frame.width + 10
            }
        } else {
            infoView.centerX(y: size.height - 20 - 15)
        }
        
        transition.updateFrame(view: backgroundView, frame: size.bounds)

        dismiss.setFrameOrigin(NSMakePoint(10, 10))

        giftView.centerX(y: 30)
        textView.centerX(y: infoView.frame.minY - textView.frame.height - 5)
        updateBackground(animated: false)
    }
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }

    private func updateBackground(animated: Bool) {
        guard let item = item as? HeaderItem, let content = item.backgroundContent else {
            backgroundView.isHidden = true
            return
        }
        backgroundView.isHidden = false
        backgroundView.update(context: item.context, content: content, style: .header(patternCenterY: giftView.frame.midY + 16), animated: animated)
    }
}


private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let dismiss:()->Void
    public let toggleMode: ()->Void
    public let toggleSection:(StarGift_Builder_Section)->Void
    public let selectAttribute:(StarGift.UniqueGift.Attribute, StarGift_Builder_Section)->Void
    public let makeNextPattern:()->Void
    public let toggleModelFilter:()->Void
    public init(context: (any AccountContextProtocol), dismiss:@escaping()->Void, toggleMode:@escaping()->Void, toggleSection: @escaping(StarGift_Builder_Section)->Void, selectAttribute:@escaping(StarGift.UniqueGift.Attribute, StarGift_Builder_Section)->Void, makeNextPattern:@escaping()->Void, toggleModelFilter:@escaping()->Void) {
        self.context = context
        self.dismiss = dismiss
        self.toggleMode = toggleMode
        self.toggleSection = toggleSection
        self.selectAttribute = selectAttribute
        self.makeNextPattern = makeNextPattern
        self.toggleModelFilter = toggleModelFilter
    }
}

private struct State : Equatable {
    public enum Mode {
        case random
        case custom
    }
    public enum ModelFilter {
        case primary
        case craftable
    }
    public var mode: Mode = .random
    public var gift: StarGift
    public var attributes: [StarGift.UniqueGift.Attribute] = []
    public var isLoading: Bool = true

    public var selected: StarGift_Builder_Section
    public var modelFilter: ModelFilter = .primary

    public var selectedModel: StarGift.UniqueGift.Attribute?
    public var selectedBackdrop: StarGift.UniqueGift.Attribute?
    public var selectedSymbol: StarGift.UniqueGift.Attribute?

    public var hasCraftableModels: Bool {
        return attributes.contains { attr in
            if case let .model(_, _, _, crafted) = attr {
                return crafted
            }
            return false
        }
    }

    public var filteredModels: [StarGift.UniqueGift.Attribute] {
        let models = attributes.filter { $0.attributeType == .model }
        guard hasCraftableModels else { return models }
        return models.filter { attr in
            if case let .model(_, _, _, crafted) = attr {
                return modelFilter == .craftable ? crafted : !crafted
            }
            return false
        }
    }

    public var primaryModelsCount: Int {
        return attributes.filter { attr in
            if case let .model(_, _, _, crafted) = attr {
                return !crafted
            }
            return false
        }.count
    }

    public var craftableModelsCount: Int {
        return attributes.filter { attr in
            if case let .model(_, _, _, crafted) = attr {
                return crafted
            }
            return false
        }.count
    }

    public var firstBackdrop: StarGift.UniqueGift.Attribute? {
        return self.attributes.first(where: { $0.attributeType == .backdrop })
    }
    public var firstSymbol: StarGift.UniqueGift.Attribute? {
        return self.attributes.first(where: { $0.attributeType == .pattern })
    }

    public var randomBackdrop: StarGift.UniqueGift.Attribute? {
        return self.attributes.filter({ $0.attributeType == .backdrop }).randomElement()
    }
    public var randomModel: StarGift.UniqueGift.Attribute? {
        return self.attributes.filter({ $0.attributeType == .model }).randomElement()
    }
    public var randomSymbol: StarGift.UniqueGift.Attribute? {
        return self.attributes.filter({ $0.attributeType == .pattern }).randomElement()
    }
}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []

    var sectionId:Int32 = 0
    var index: Int32 = 0

    if state.isLoading {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("loading"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return GeneralLoadingRowItem(initialSize, stableId: stableId, viewType: .singleItem)
        }))
        return entries
    }

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("header"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return HeaderItem(initialSize, stableId: stableId, context: arguments.context, arguments: arguments, state: state, attributes: state.attributes)
    }))

    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("segment"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return SegmentRowItem(initialSize, stableId: stableId, state: state, arguments: arguments)
    }))

    if state.hasCraftableModels {
        let currentCount = state.modelFilter == .primary ? state.primaryModelsCount : state.craftableModelsCount
        let currentType = state.modelFilter == .primary ? strings().starGiftModelBuilderPrimary : strings().starGiftModelBuilderCraftable
        let otherType = state.modelFilter == .primary ? strings().starGiftModelBuilderCraftable : strings().starGiftModelBuilderPrimary

        let text = strings().starGiftModelBuilderCollectionFeatures(currentCount, currentType)
        let linkText = strings().starGiftModelBuilderViewOtherModels(otherType)

        let attr = NSMutableAttributedString()
        attr.append(.initialize(string: text, color: theme.colors.listGrayText, font: .normal(.text)))
        attr.append(.initialize(string: linkText, color: theme.colors.accent, font: .normal(.text)))
        attr.addAttribute(NSAttributedString.Key.link, value: "toggle://filter", range: NSRange(location: text.count, length: linkText.count))

        entries.append(.desc(sectionId: sectionId, index: index, text: .attributed(attr), data: .init(viewType: .modern(position: .single, insets: .init(top: 0, bottom: 0)), fontSize: 13, centerViewAlignment: true, alignment: .center, linkExecutor: TextViewInteractions(processURL: { _ in
            arguments.toggleModelFilter()
        }))))
    } else {
        let modelsCount = state.attributes.filter({ $0.attributeType == .model}).count
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().starGiftModelBuilderCollectionFeaturesOther(modelsCount)), data: .init( viewType: .modern(position: .single, insets: .init(top: 0, bottom: 0)), fontSize: 13, centerViewAlignment: true, alignment: .center)))
    }
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(5)))
    sectionId += 1

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("grid"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return GridRowItem(initialSize, stableId: stableId, state: state, arguments: arguments)
    }))

    return entries
}

public func StarGift_ModelBuilderController(context: (any AccountContextProtocol), gift: StarGift, giftId: Int64, defaultMode: StarGift_Builder_Section = .models, onlyCraftedModels: Bool = false) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let initialState = State(gift: gift, selected: defaultMode, modelFilter: onlyCraftedModels ? .craftable : .primary)

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var getController:(()->ViewController?)? = nil
    var close:(()->Void)? = nil
    var window:Window {
        get {
            return getController?()?.window ?? context.window
        }
    }

    let arguments = Arguments(context: context, dismiss: {
        close?()
    }, toggleMode: {
        updateState { current in
            var current = current
            current.mode = current.mode == .custom ? .random : .custom
            
            if current.mode == .random {
                current.selectedModel = current.randomModel
                current.selectedBackdrop = current.randomBackdrop
                current.selectedSymbol = current.randomSymbol
            }
            
            return current
        }
    }, toggleSection: { value in
        updateState { current in
            var current = current
            current.selected = value
            return current
        }
    }, selectAttribute: { attr, mode in
        updateState { current in
            var current = current
            switch mode {
            case .models:
                current.selectedModel = attr
            case .backdrops:
                current.selectedBackdrop = attr
            case .symbols:
                current.selectedSymbol = attr
            }
            current.mode = .custom
            return current
        }
    }, makeNextPattern: {
        updateState { current in
            var current = current

            if current.mode == .random {
                current.selectedModel = current.randomModel
                current.selectedBackdrop = current.randomBackdrop
                current.selectedSymbol = current.randomSymbol
            }

            return current
        }
    }, toggleModelFilter: {
        updateState { current in
            var current = current
            current.modelFilter = current.modelFilter == .primary ? .craftable : .primary
            current.selected = .models
            return current
        }
    })
    
    actionsDisposable.add((context.engine.payments.getStarGiftUpgradeAttributes(giftId: giftId)
    |> deliverOnMainQueue).startStrict(next: { attributes in
        if let attributes = attributes {
            updateState { current in
                var current = current

                current.attributes = attributes
                current.isLoading = false

                switch gift {
                case let .unique(uniqueGift):
                    for attribute in uniqueGift.attributes {
                        switch attribute {
                        case .backdrop:
                            if let index = current.attributes.firstIndex(where: { $0.name == attribute.name }) {
                                current.selectedBackdrop = current.attributes[index]
                            }
                        case .model:
                            if let index = current.attributes.firstIndex(where: { $0.name == attribute.name }) {
                                current.selectedModel = current.attributes[index]
                            }
                        case .pattern:
                            if let index = current.attributes.firstIndex(where: { $0.name == attribute.name }) {
                                current.selectedSymbol = current.attributes[index]
                            }
                        default:
                            break
                        }
                        if let index = current.attributes.firstIndex(where: { $0.name == attribute.name }) {
                            current.attributes.move(at: index, to: 0)
                        }
                    }
                    current.mode = .custom
                default:
                    break
                }

                if current.mode == .random {
                    current.selectedModel = current.randomModel
                    current.selectedBackdrop = current.randomBackdrop
                    current.selectedSymbol = current.randomSymbol
                }

                return current
            }
        }
    }))

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

//    let modalInteractions = ModalInteractions(acceptTitle: "OK", accept: { [weak controller] in
//        _ = controller?.returnKeyAction()
//    }, singleButton: true)
    
    let modalController = InputDataModalController(controller, modalInteractions: nil, size: NSMakeSize(360, 380))
    modalController._hasBorder = false
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController

}

