import Cocoa
import TGUIKit
import CalendarUtils
import TelegramTheme
import GeneralRows

open class CalendarControllerView : View {
    
}

private final class CalendarNavigation : NavigationViewController {
    
    
   
}

open class CalendarController: GenericViewController<CalendarControllerView> {
    
    private var navigation:CalendarNavigation!
    private var interactions:CalendarMonthInteractions!
    private let onlyFuture: Bool
    private let lowYear: Int
    private let current: Date
    private let limitedBy: Date?
    open override func viewDidLoad() {
        super.viewDidLoad()
        addSubview(navigation.view)
        readyOnce()
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.navigation.viewDidAppear(animated)
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            if let current = self?.navigation.controller as? CalendarMonthController, current.isPrevEnabled, let backAction = self?.interactions.backAction {
                backAction(current.month.month)
            }
            return .invoked
        }, with: self, for: .LeftArrow, priority: .modal)
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            if let current = self?.navigation.controller as? CalendarMonthController, current.isNextEnabled, let nextAction = self?.interactions.nextAction {
                nextAction(current.month.month)
            }
            return .invoked
        }, with: self, for: .RightArrow, priority: .modal)
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.navigation.viewWillDisappear(animated)
        self.window?.remove(object: self, for: .LeftArrow)
        self.window?.remove(object: self, for: .RightArrow)
    }
    
    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.navigation.viewDidDisappear(animated)
    }
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigation.viewWillAppear(animated)
    }
    
    public init(_ frameRect:NSRect, _ window: Window, current: Date = Date(), onlyFuture: Bool = false, limitedBy: Date? = nil, lowYear: Int = 2013, canBeNoYear: Bool = false, selectHandler:@escaping (Date)->Void, autoclose: Bool = true) {
        self.onlyFuture = onlyFuture
        self.current = current
        self.limitedBy = limitedBy
        self.lowYear = lowYear
        super.init(frame: frameRect)
        bar = .init(height: 0)
        self.interactions = CalendarMonthInteractions(lowYear: lowYear, canBeNoYear: canBeNoYear, selectAction: { [weak self] (selected) in
            if autoclose {
                self?.popover?.hide()
                self?.navigationController?.modal?.close()
            }
            selectHandler(selected)
        }, backAction: { [weak self] date in
            if let strongSelf = self {
                strongSelf.navigation.push(strongSelf.stepMonth(date: CalendarUtils.stepMonth(-1, date: date)), style: .pop)
            }
        }, nextAction: { [weak self] date in
            if let strongSelf = self {
                strongSelf.navigation.push(strongSelf.stepMonth(date: CalendarUtils.stepMonth(1, date: date)), style: .push)
            }
        }, changeYear: { [weak self] year, date in
            if let strongSelf = self {
                strongSelf.navigation.push(strongSelf.stepMonth(date: CalendarUtils.year(Int(year), date: date)), style: .push)
            }
        })
        
        self.navigation = CalendarNavigation(stepMonth(date: current), window)
        self.navigation._frameRect = frameRect
        
    }
    
    open func stepMonth(date:Date, selectDayAnyway: Bool = false) -> CalendarMonthController {
        return CalendarMonthController(date, onlyFuture: self.onlyFuture, limitedBy: limitedBy, selectDayAnyway: !selectDayAnyway ? CalendarUtils.isSameDate(current, date: date, checkDay: false) : true, interactions: interactions, lowYear: self.lowYear)
    }
    
    open var date: Date {
        return (self.navigation.controller as! CalendarMonthController).date
    }
    
    open func hideYear() {
        let day = Calendar.current.component(.day, from: date)
        self.navigation.push(self.stepMonth(date: CalendarUtils.year(Int(1), date: date, day: day), selectDayAnyway: true), style: ViewControllerStyle.none)
    }
    
    open override var isAutoclosePopover: Bool {
        return false
    }
}



