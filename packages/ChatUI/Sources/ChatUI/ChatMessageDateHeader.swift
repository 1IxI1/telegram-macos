import Cocoa
import TGUIKit
import TelegramCore
import CalendarUtils
import Postbox
import ChatHistoryModel
import InAppSettings
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils




private let timezoneOffset: Int32 = {
    let nowTimestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
    var now: time_t = time_t(nowTimestamp)
    var timeinfoNow: tm = tm()
    localtime_r(&now, &timeinfoNow)
    return Int32(timeinfoNow.tm_gmtoff)
}()

private let formatter = DateFormatter()
private let granularity: Int32 = 60 * 60 * 24



public class ChatDateStickItem : TableStickItem {
    
    private let entry:ChatHistoryEntry
    public let timestamp:Int32
    fileprivate let chatInteraction:ChatInteraction?
    public let isBubbled: Bool
    public let layout:TextViewLayout
    public let presentation: TelegramPresentationTheme
    
    public var monoforumState: MonoforumUIState? {
        return entry.additionalData.monoforumState
    }
    
    public init(_ initialSize:NSSize, _ entry:ChatHistoryEntry, interaction: ChatInteraction, theme: TelegramPresentationTheme) {
        self.entry = entry
        self.isBubbled = entry.renderType == .bubble
        self.chatInteraction = interaction
        self.presentation = theme
        if case let .DateEntry(index, _, _, _) = entry {
            self.timestamp = index.timestamp
        } else {
            fatalError()
        }
        
        let nowTimestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
        
        var t: time_t = time_t(timestamp)
        var timeinfo: tm = tm()
        localtime_r(&t, &timeinfo)
        
        var now: time_t = time_t(nowTimestamp)
        var timeinfoNow: tm = tm()
        localtime_r(&now, &timeinfoNow)
        
        var text: String
        if timeinfo.tm_year == timeinfoNow.tm_year && timeinfo.tm_yday == timeinfoNow.tm_yday {
            
            switch interaction.mode {
            case .scheduled:
                text = strings().chatDateScheduledForToday
            default:
                text = strings().dateToday
            }
            
        } else {
            let dateFormatter = formatter
            
            dateFormatter.calendar = Calendar.current
            //dateFormatter.timeZone = NSTimeZone.local
            dateFormatter.dateFormat = "dd MMMM";
            //&& (timeinfoNow.tm_mon >= timeinfo.tm_mon || (timeinfoNow.tm_year - timeinfo.tm_year) >= 2)
            if timeinfoNow.tm_year > timeinfo.tm_year  {
                dateFormatter.dateFormat = "dd MMMM yyyy";
            } else if timeinfoNow.tm_year < timeinfo.tm_year {
                dateFormatter.dateFormat = "dd MMMM yyyy";
            }
            let dateString = dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
            switch interaction.mode {
            case .scheduled:
                if timestamp - 2147460000 > 0 {
                    text = strings().chatDateScheduledUntilOnline
                } else {
                    text = strings().chatDateScheduledFor(dateString)
                }
            default:
                text = dateString
            }
        }
        
        
        self.layout = TextViewLayout(.initialize(string: text, color: presentation.chatServiceItemTextColor, font: .medium(presentation.fontSize)), maximumNumberOfLines: 1, truncationType: .end, alignment: .center)

        
        super.init(initialSize)
    }
    
    public var shouldBlurService: Bool {
        if TelegramUtilsHooks.shared.isLite(.blur) {
            return false
        }
        return presentation.shouldBlurService
    }
    
    public override var canBeAnchor: Bool {
        return false
    }
    
    public required init(_ initialSize: NSSize) {
        entry = .DateEntry(MessageIndex.absoluteLowerBound(), .list, theme, .init())
        timestamp = 0
        self.isBubbled = false
        self.layout = TextViewLayout(NSAttributedString())
        self.chatInteraction = nil
        self.presentation = theme
        super.init(initialSize)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        layout.measure(width: width - 40)
        return success
    }
    
    public override var stableId: AnyHashable {
        return entry.stableId
    }
    
    public override var height: CGFloat {
        return 30
    }
    
    public override func viewClass() -> AnyClass {
        return ChatDateStickView.self
    }
    
    
}

public class ChatDateStickView : TableStickView {
    private let textView:TextView
    private let containerView: Control = Control()
    private var appliedColors: (presentation: TelegramPresentationTheme, shouldBlurService: Bool)?
    public required init(frame frameRect: NSRect) {
        
        
        
        self.textView = TextView()
        self.textView.isSelectable = false
       // self.textView.userInteractionEnabled = false
        self.containerView.wantsLayer = true
//        self.textView.disableBackgroundDrawing = true
       // textView.isEventLess = false
        super.init(frame: frameRect)
        addSubview(textView)
        
        textView.set(handler: { [weak self] control in
             if let strongSelf = self, let item = strongSelf.item as? ChatDateStickItem, let table = item.table {
                
                let row = table.visibleRows()
                var ignore: Bool = false
                if row.length > 1 {
                    if let underItem = table.item(at: row.location + row.length - 1) as? ChatDateStickItem {
                       ignore = item.timestamp == underItem.timestamp
                    }
                }
                
                if strongSelf.header && !ignore {
                    var calendar = NSCalendar.current
                    
                    calendar.timeZone = TimeZone(abbreviation: "UTC")!
                    let date = Date(timeIntervalSince1970: TimeInterval(item.timestamp + 86400))
                    let components = calendar.dateComponents([.year, .month, .day], from: date)
                    
                    item.chatInteraction?.jumpToDate(CalendarUtils.monthDay(components.day!, date: date))
                } else if let chatInteraction = item.chatInteraction, chatInteraction.mode == .history {
                    if !hasPopover(chatInteraction.interactionContext.window) {
                        if let controller = ChatNavigationHooks.shared.makeCalendarPopover(chatInteraction.interactionContext.window, Date(timeIntervalSince1970: TimeInterval(item.timestamp)), chatInteraction.jumpToDate) {
                            showPopover(for: control, with: controller, edge: .maxY, inset: NSMakePoint(-84, -40))
                        }
                    }
                }
               
            }
        }, for: .Click)
    }
    
    public override func hitTest(_ point: NSPoint) -> NSView? {
        return header && textView.layer?.opacity == 0 ? nil : super.hitTest(point)
    }
    
    public override func mouseDown(with event: NSEvent) {
        guard header, let tableView = superview as? TableView else {
            super.mouseDown(with: event)
            return
        }
        
        tableView.documentView!.hitTest(tableView.documentView!.convert(event.locationInWindow, from: nil))?.mouseDown(with: event)
        
    }
    
    public override func mouseUp(with event: NSEvent) {
        guard header, let tableView = superview as? TableView else {
            super.mouseUp(with: event)
            return
        }

        tableView.documentView!.hitTest(tableView.documentView!.convert(event.locationInWindow, from: nil))?.mouseUp(with: event)
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func updateIsVisible(_ visible: Bool, animated: Bool) {
        textView.change(opacity: visible ? 1 : 0, animated: animated)
    }
    
    
    public override var header: Bool {
        didSet {
            updateColors()
        }
    }
    
    
    public override func updateColors() {
        super.updateColors()
        
        if let item = item as? ChatDateStickItem {
            var presentation = item.presentation
            if let table = item.table {
                table.enumerateItems(with: { item in
                    if let item = item as? ChatRowItem {
                        presentation = item.presentation
                        return false
                    } else if let item = item as? ChatDateStickItem {
                        presentation = item.presentation
                        return false
                    }
                    return true
                })
            }
            let shouldBlurService = item.shouldBlurService
            if let appliedColors = self.appliedColors, appliedColors.presentation === presentation, appliedColors.shouldBlurService == shouldBlurService {
                return
            }
            self.appliedColors = (presentation, shouldBlurService)
            if shouldBlurService {
                textView.blurBackground = presentation.blurServiceColor
                textView.backgroundColor = .clear
            } else {
                textView.backgroundColor = presentation.chatServiceItemColor
                textView.blurBackground = nil
            }
        }
        
    }
    
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        guard let item = item as? ChatDateStickItem else {
            return
        }
        
        let rect = textView.centerFrame().offsetBy(dx: item.monoforumState == .vertical ? 40 : 0, dy: 0)
        
        transition.updateFrame(view: textView, frame: rect)
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        if let item = item as? ChatDateStickItem {
            textView.update(item.layout)
            textView.setFrameSize(item.layout.layoutSize.width + 16, item.layout.layoutSize.height + 6)
            textView.layer?.cornerRadius = textView.frame.height / 2

        }
        super.set(item: item, animated:animated)
        
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate
        
        self.updateLayout(size: self.frame.size, transition: transition)
    }
    
    public override func onInsert(_ animation: NSTableView.AnimationOptions, appearAnimated: Bool) {
        if let item = item as? ChatDateStickItem, !TelegramUtilsHooks.shared.isLite(.animations) {
            if item.isBubbled, appearAnimated {
                self.textView.layer?.animateScaleSpring(from: 0.5, to: 1, duration: 0.4, bounce: false)
                self.textView.layer?.animateAlpha(from: 0, to: 1, duration: 0.35)
            }
        }
    }
}
