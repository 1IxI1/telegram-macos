import AppKit

public struct AnimatableContentObserverOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    public static let contentBounds = AnimatableContentObserverOptions(rawValue: 1 << 0)
    public static let documentFrame = AnimatableContentObserverOptions(rawValue: 1 << 1)
    public static let ownFrame = AnimatableContentObserverOptions(rawValue: 1 << 2)
    public static let ownBounds = AnimatableContentObserverOptions(rawValue: 1 << 3)
}

public final class AnimatableContentObserver {
    private weak var observedWindow: NSWindow?
    private weak var observedContentView: NSView?
    private weak var observedDocumentView: NSView?
    private var registered: Bool = false
    
    public init() {
    }
    
    public func update(for view: NSView, target: AnyObject, selector: Selector, options: AnimatableContentObserverOptions = [.contentBounds, .documentFrame]) {
        self.update(for: view, target: target, selector: selector, contentView: view.enclosingScrollView?.contentView, documentView: view.enclosingScrollView?.documentView, options: options)
    }
    
    public func update(for view: NSView, target: AnyObject, selector: Selector, contentView: NSView?, documentView: NSView?, options: AnimatableContentObserverOptions) {
        guard let window = view.window else {
            return
        }
        
        if registered
            && observedWindow === window
            && observedContentView === contentView
            && observedDocumentView === documentView {
            return
        }
        
        let center = NotificationCenter.default
        if registered {
            center.removeObserver(target)
        }
        center.addObserver(target, selector: selector, name: NSWindow.didBecomeKeyNotification, object: window)
        center.addObserver(target, selector: selector, name: NSWindow.didResignKeyNotification, object: window)
        if options.contains(.contentBounds) {
            center.addObserver(target, selector: selector, name: NSView.boundsDidChangeNotification, object: contentView)
        }
        if options.contains(.ownBounds) {
            center.addObserver(target, selector: selector, name: NSView.boundsDidChangeNotification, object: view)
        }
        if options.contains(.documentFrame) {
            center.addObserver(target, selector: selector, name: NSView.frameDidChangeNotification, object: documentView)
        }
        if options.contains(.ownFrame) {
            center.addObserver(target, selector: selector, name: NSView.frameDidChangeNotification, object: view)
        }
        observedWindow = window
        observedContentView = contentView
        observedDocumentView = documentView
        registered = true
    }
}

public final class AnimatableContentTokenObserver {
    private weak var observedWindow: NSWindow?
    private weak var observedContentView: NSView?
    private weak var observedDocumentView: NSView?
    private var tokens: [NSObjectProtocol] = []
    
    public init() {
    }
    
    public func update(for view: NSView, handler: @escaping (Notification) -> Void) {
        guard let w = view.window else {
            return
        }
        let cv = view.enclosingScrollView?.contentView
        let dv = view.enclosingScrollView?.documentView

        if !tokens.isEmpty
            && observedWindow === w
            && observedContentView === cv
            && observedDocumentView === dv {
            return
        }

        let center = NotificationCenter.default
        for token in tokens {
            center.removeObserver(token)
        }
        tokens.removeAll()

        tokens.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main, using: handler))
        tokens.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: w, queue: .main, using: handler))
        tokens.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: cv, queue: .main, using: handler))
        tokens.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: dv, queue: .main, using: handler))
        observedWindow = w
        observedContentView = cv
        observedDocumentView = dv
    }
    
    public func removeObservers() {
        let center = NotificationCenter.default
        for token in tokens {
            center.removeObserver(token)
        }
        tokens.removeAll()
    }
}
