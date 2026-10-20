#if DEBUG
import Cocoa
import ImageIO
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramContext
import PerfLab
import InputView
import InputTextView

enum ChatFloatingDebug {
    static var moves = 0
    static var violations = 0
}

public enum ChatNavigationLab {
    private static var session: AnyObject?
    private static var didStart = false

    @discardableResult
    public static func startIfRequested(context: any AccountContextProtocol, outputDirectory: URL) -> Bool {
        guard !self.didStart, let configuration = PerfLabConfiguration.fromLaunchArguments(defaultOutputDirectory: outputDirectory), configuration.lab == "chat-navigation" else {
            return false
        }
        self.didStart = true
        Queue.mainQueue().after(configuration.double("-PerfLabStartDelay", 4.0), {
            let session = ChatNavigationLabSession(context: context, configuration: configuration, completion: {
                ChatNavigationLab.session = nil
                if configuration.quitWhenDone {
                    NSApp.terminate(nil)
                }
            })
            ChatNavigationLab.session = session
            session.start()
        })
        return true
    }
}

private final class ChatNavigationLabSession {
    private let context: any AccountContextProtocol
    private let configuration: PerfLabConfiguration
    private let completion: () -> Void
    private let report: PerfLabReport
    private let processMonitor = PerfLabProcessMonitor()
    private var controller: (any ChatControllerKind)?
    private var loadDisposable: Disposable?
    private var navigationIndex = 0
    private var namePrefix = ""
    private var chatNotes: [String: String] = [:]

    init(context: any AccountContextProtocol, configuration: PerfLabConfiguration, completion: @escaping () -> Void) {
        self.context = context
        self.configuration = configuration
        self.completion = completion
        self.report = PerfLabReport(configuration: configuration)
    }

    func start() {
        if self.configuration.scenarios.contains("sweep") {
            self.startSweep()
            return
        }
        let context = self.context
        if self.configuration.double("-PerfLabSavedMessages", 0.0) != 0 {
            self.chatNotes = ["chat": "Saved Messages"]
            self.open(peerId: context.peerId)
            return
        }
        let username = self.configuration.string("-PerfLabChannel", "")
        let title = self.configuration.string("-PerfLabPeerTitle", "INVEST ZONE")
        let peerSignal: Signal<PeerId?, NoError>
        if !username.isEmpty {
            peerSignal = context.engine.peers.resolvePeerByName(name: username, referrer: nil)
            |> mapToSignal { result -> Signal<PeerId?, NoError> in
                if case let .result(peer) = result {
                    return .single(peer?.id)
                }
                return .complete()
            }
            |> take(1)
        } else {
            peerSignal = context.engine.contacts.searchLocalPeers(query: title)
            |> map { peers -> PeerId? in
                return peers.first(where: { $0.peer?._asPeer().isChannel == true })?.peerId ?? peers.first?.peerId
            }
            |> take(1)
        }
        self.loadDisposable = (peerSignal |> deliverOnMainQueue).start(next: { [weak self] peerId in
            guard let self else {
                return
            }
            guard let peerId else {
                self.report.add(scenario: "open", run: 0, metrics: [:], notes: ["error": "peer not found"])
                self.finish()
                return
            }
            self.chatNotes = ["chat": username.isEmpty ? title : username]
            self.open(peerId: peerId)
        })
    }

    private func makeChatController<C: AccountContextProtocol>(context: C, peerId: PeerId) -> any ChatControllerKind {
        return ChatController(context: context, chatLocation: .peer(peerId))
    }

    private func open(peerId: PeerId) {
        let controller = self.makeChatController(context: self.context, peerId: peerId)
        self.controller = controller
        self.context.bindings.rootNavigation().push(controller)
        Queue.mainQueue().after(self.configuration.double("-PerfLabOpenWait", 5.0), { [weak self] in
            self?.runScenarios(self?.configuration.scenarios ?? [])
        })
    }

    private func finish() {
        let url = self.report.write()
        NSLog("PerfLab report written to %@", url?.path ?? "nil")
        self.completion()
    }

    private func runScenarios(_ scenarios: [String]) {
        guard let scenario = scenarios.first else {
            self.finish()
            return
        }
        let rest = Array(scenarios.dropFirst())
        let next: () -> Void = { [weak self] in
            Queue.mainQueue().after(1.5, {
                self?.runScenarios(rest)
            })
        }
        switch scenario {
        case "pinned":
            self.runPinned(remaining: Int(self.configuration.double("-PerfLabPinnedClicks", 8.0)), completion: next)
        case "jump":
            self.waitForPinned(attempts: 40, completion: { [weak self] in
                guard let self else {
                    return
                }
                let targets = self.controller?.chatInteraction.presentation.pinnedMessageId.map { [$0.messageId] + $0.others } ?? []
                if targets.isEmpty {
                    self.report.add(scenario: "jump", run: 0, metrics: [:], notes: ["error": "no pinned messages"])
                }
                self.runJumps(targets: Array(Set(targets)).sorted(by: { $0.id > $1.id }), completion: next)
            })
        case "scroll":
            if self.configuration.double("-PerfLabFloatWindow", 1.0) != 0, let window = self.controller?.genericView.tableView.window {
                window.level = .floating
                window.orderFrontRegardless()
            }
            if self.configuration.double("-PerfLabStripHidden", 0.0) != 0, let root = self.controller?.genericView.tableView.window?.contentView {
                var stripped: [NSView] = []
                func walk(_ view: NSView) {
                    for subview in view.subviews {
                        let onlyGlass = self.configuration.double("-PerfLabStripHidden", 0.0) == 2
                        if subview.isHidden && (!onlyGlass || String(describing: type(of: subview)).contains("Glass")) {
                            stripped.append(subview)
                        } else {
                            walk(subview)
                        }
                    }
                }
                walk(root)
                var owners: [String: Int] = [:]
                for view in stripped {
                    owners["\(type(of: view))<\(view.superview.map { String(describing: type(of: $0)) } ?? "-")", default: 0] += 1
                }
                for view in stripped {
                    view.removeFromSuperview()
                }
                self.chatNotes["stripped"] = "\(stripped.count)"
                self.chatNotes["owners"] = owners.sorted(by: { $0.value > $1.value }).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            }
            self.calibrateWheel(completion: { [weak self] in
                self?.runScrollPasses(index: 0, completion: next)
            })
        case "snapshot":
            self.runSnapshots(index: 0, completion: next)
        case "typing":
            self.runTyping(index: 0, completion: next)
        case "resize":
            self.runResize(index: 0, completion: next)
        case "selection":
            self.runSelection(index: 0, completion: next)
        case "viewcount":
            if let window = self.controller?.genericView.tableView.window, let root = window.contentView {
                var total = 0
                var hidden = 0
                var layers = 0
                var classes: [String: Int] = [:]
                var hiddenClasses: [String: Int] = [:]
                func walk(_ view: NSView, parentHidden: Bool) {
                    total += 1
                    let isHidden = parentHidden || view.isHidden
                    if isHidden {
                        hidden += 1
                        hiddenClasses[String(describing: type(of: view)), default: 0] += 1
                    }
                    classes[String(describing: type(of: view)), default: 0] += 1
                    layers += view.layer?.sublayers?.count ?? 0
                    for subview in view.subviews {
                        walk(subview, parentHidden: isHidden)
                    }
                }
                walk(root, parentHidden: false)
                let table = self.controller?.genericView.tableView
                let top = classes.sorted(by: { $0.value > $1.value }).prefix(25).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                let topHidden = hiddenClasses.sorted(by: { $0.value > $1.value }).prefix(15).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                self.report.add(scenario: "viewcount", run: 0, metrics: ["views": Double(total), "hiddenViews": Double(hidden), "sublayers": Double(layers), "tableSubviews": Double(table?.documentView?.subviews.count ?? 0), "visibleRows": Double(table?.visibleRows().length ?? 0)], notes: ["top": top, "hidden": topHidden])
            }
            next()
        case "census":
            Queue.mainQueue().after(self.configuration.double("-PerfLabCensusDelay", 3.0), { [weak self] in
                guard let self else {
                    return
                }
                if let root = self.controller?.genericView.tableView.window?.contentView {
                    let census = PerfLabViewCensus.take(root)
                    var metrics = census.metrics
                    metrics["footprintMB"] = Double(self.processMonitor.snapshot().footprint) / 1048576.0
                    self.report.add(scenario: "census", run: 0, metrics: metrics, notes: census.notes(top: 60).merging(self.chatNotes, uniquingKeysWith: { $1 }))
                }
                next()
            })
        case "idle":
            self.runIdle(index: 0, completion: next)
        case "open":
            self.runOpens(remaining: Int(self.configuration.double("-PerfLabOpens", 6.0)), index: 0, completion: next)
        case "pininfo":
            guard let peerId = self.controller?.chatInteraction.peerId else {
                next()
                return
            }
            let signal = self.context.engine.messages.searchMessages(location: .peer(peerId: peerId, fromId: nil, tags: .pinned, reactions: nil, threadId: nil, minDate: nil, maxDate: nil), query: "", state: nil, limit: 50)
            |> take(1)
            self.loadDisposable = (signal |> deliverOnMainQueue).start(next: { [weak self] result in
                var notes: [String: String] = [:]
                for message in result.0.messages {
                    notes["m\(message.id.id)"] = "threadId=\(message.threadId.map { "\($0)" } ?? "nil")"
                }
                notes["peerKind"] = self?.controller?.chatInteraction.presentation.peer.map { "\(type(of: $0))" } ?? "?"
                notes["pinned"] = self?.controller?.chatInteraction.presentation.pinnedMessageId.map { "\($0.messageId.id) others=\($0.others.map { $0.id })" } ?? "nil"
                self?.report.add(scenario: "pininfo", run: 0, metrics: [:], notes: notes)
                next()
            })
        default:
            self.report.add(scenario: scenario, run: 0, metrics: [:], notes: ["error": "unknown scenario"])
            next()
        }
    }

    private var wheelSign: Double = 1
    private var scrollMeasurement: PerfLabScrollMeasurement?
    private var openPeerId: PeerId?

    private func lowestVisibleMessageId() -> Int32? {
        guard let table = self.controller?.genericView.tableView else {
            return nil
        }
        let range = table.visibleRows()
        var result: Int32?
        if range.length > 0 {
            for row in range.location ..< range.location + range.length {
                if let item = table.item(at: row) as? ChatRowItem, let id = item.messages.first?.id.id {
                    result = min(result ?? id, id)
                }
            }
        }
        return result
    }

    private func calibrateWheel(completion: @escaping () -> Void) {
        guard let table = self.controller?.genericView.tableView else {
            completion()
            return
        }
        let before = self.lowestVisibleMessageId()
        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 400, wheel2: 0, wheel3: 0), let nsEvent = NSEvent(cgEvent: event) {
            table.scrollWheel(with: nsEvent)
        }
        Queue.mainQueue().after(0.6, { [weak self] in
            guard let self else {
                return
            }
            let after = self.lowestVisibleMessageId()
            if let before, let after {
                self.wheelSign = after < before ? 1 : -1
            }
            self.controller?.chatInteraction.scrollToLatest(false)
            Queue.mainQueue().after(1.0, completion)
        })
    }

    private func runScrollPasses(index: Int, completion: @escaping () -> Void) {
        let runs = Int(self.configuration.double("-PerfLabRuns", 2.0))
        guard index <= runs, let table = self.controller?.genericView.tableView else {
            completion()
            return
        }
        let speed = self.configuration.double("-PerfLabScrollSpeed", 2400.0)
        let duration = self.configuration.double("-PerfLabScrollDuration", 7.0)
        let segments = [
            PerfLabScrollSegment(duration: 0.2, velocity: 0),
            PerfLabScrollSegment(duration: duration, velocity: speed),
            PerfLabScrollSegment(duration: duration, velocity: -speed),
            PerfLabScrollSegment(duration: 0.2, velocity: 0)
        ]
        let measurement = PerfLabScrollMeasurement(view: table, scrollView: table, segments: segments, wheelSign: self.wheelSign, processMonitor: self.processMonitor, sampler: { [weak table] in
            guard let table else {
                return [:]
            }
            var avatarsBelowRows = 0
            if let subviews = table.documentView?.subviews, let lastRow = subviews.lastIndex(where: { !($0 is ChatAvatarView) }) {
                avatarsBelowRows = subviews.prefix(lastRow).filter { $0 is ChatAvatarView }.count
            }
            return ["rows": Double(table.count), "avatarsBelowRows": Double(avatarsBelowRows)]
        })
        self.scrollMeasurement = measurement
        let name = index == 0 ? "scroll-warmup" : "scroll"
        measurement.run(completion: { [weak self] metrics in
            guard let self else {
                return
            }
            self.scrollMeasurement = nil
            let notes = self.chatNotes.merging(["wheelSign": "\(self.wheelSign)"], uniquingKeysWith: { $1 })
            var metrics = metrics
            metrics["floatingMoves"] = Double(ChatFloatingDebug.moves)
            metrics["floatingOrderViolations"] = Double(ChatFloatingDebug.violations)
            ChatFloatingDebug.moves = 0
            ChatFloatingDebug.violations = 0
            self.report.add(scenario: name, run: max(0, index - 1), metrics: metrics, notes: notes)
            self.controller?.chatInteraction.scrollToLatest(false)
            Queue.mainQueue().after(2.0, {
                self.runScrollPasses(index: index + 1, completion: completion)
            })
        })
    }

    private func captureWindow(_ window: NSWindow, name: String) {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            let createImage = unsafeBitCast(symbol, to: CreateImage.self)
            if let image = createImage(.null, CGWindowListOption.optionIncludingWindow.rawValue, UInt32(window.windowNumber), CGWindowImageOption.boundsIgnoreFraming.rawValue | CGWindowImageOption.nominalResolution.rawValue)?.takeRetainedValue() {
                let url = self.configuration.outputDirectory.appendingPathComponent("chat-navigation-\(self.configuration.label)-\(name).png")
                if let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
                    CGImageDestinationAddImage(destination, image, nil)
                    CGImageDestinationFinalize(destination)
                }
            }
        }
    }

    private func runSnapshots(index: Int, completion: @escaping () -> Void) {
        let count = Int(self.configuration.double("-PerfLabSnapshots", 3.0))
        guard index < count, let table = self.controller?.genericView.tableView, let window = table.window else {
            completion()
            return
        }
        self.captureWindow(window, name: "snapshot\(index)")
        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(1200 * self.wheelSign), wheel2: 0, wheel3: 0), let nsEvent = NSEvent(cgEvent: event) {
            table.scrollWheel(with: nsEvent)
        }
        Queue.mainQueue().after(1.5, { [weak self] in
            self?.runSnapshots(index: index + 1, completion: completion)
        })
    }

    private func runTyping(index: Int, completion: @escaping () -> Void) {
        let runs = Int(self.configuration.double("-PerfLabRuns", 2.0))
        guard index < runs, let controller = self.controller, controller.chatInteraction.peerId == self.context.peerId else {
            completion()
            return
        }
        let textView = controller.genericView.inputView.textView.view.textView
        let table = controller.genericView.tableView
        let text = Array("The quick brown fox jumps over the lazy dog while the chat keeps scrolling smoothly, and every keystroke should stay cheap. ")
        let interval = 1.0 / self.configuration.double("-PerfLabTypingRate", 15.0)
        let clock = PerfLabFrameClock(view: table)
        let start = self.processMonitor.snapshot()
        let startUnixTime = Date().timeIntervalSince1970
        clock.start()
        func type(_ position: Int) {
            if position < text.count {
                textView.insertText(String(text[position]), replacementRange: NSRange(location: NSNotFound, length: 0))
                Queue.mainQueue().after(interval, {
                    type(position + 1)
                })
                return
            }
            clock.stop()
            let end = self.processMonitor.snapshot()
            let elapsed = max(0.001, end.time - start.time)
            self.report.add(scenario: "typing", run: index, metrics: [
                "characters": Double(text.count),
                "cpuCores": (end.cpuTime - start.cpuTime) / elapsed,
                "mainThreadBusyPercent": (end.mainThreadCpuTime - start.mainThreadCpuTime) / elapsed * 100,
                "mainMsPerCharacter": (end.mainThreadCpuTime - start.mainThreadCpuTime) * 1000 / Double(text.count),
                "hitches": Double(clock.stats.hitches),
                "worstGapMs": clock.stats.worstGap * 1000,
                "startUnixTime": startUnixTime,
                "endUnixTime": Date().timeIntervalSince1970
            ], notes: self.chatNotes)
            if self.configuration.double("-PerfLabTypingSnapshot", 0.0) != 0, let window = table.window {
                self.captureWindow(window, name: "typing\(index)")
            }
            textView.selectAll(nil)
            textView.deleteBackward(nil)
            Queue.mainQueue().after(2.0, { [weak self] in
                self?.runTyping(index: index + 1, completion: completion)
            })
        }
        type(0)
    }

    private func runResize(index: Int, completion: @escaping () -> Void) {
        let runs = Int(self.configuration.double("-PerfLabRuns", 2.0))
        guard index < runs, let table = self.controller?.genericView.tableView, let window = table.window else {
            completion()
            return
        }
        let original = window.frame
        let delta = CGFloat(self.configuration.double("-PerfLabResizeDelta", 240.0))
        let steps = Int(self.configuration.double("-PerfLabResizeSteps", 30.0))
        var widths: [CGFloat] = []
        for i in 0 ... steps {
            widths.append(original.width - delta * CGFloat(i) / CGFloat(steps))
        }
        widths += widths.reversed()
        let clock = PerfLabFrameClock(view: table)
        let start = self.processMonitor.snapshot()
        let startUnixTime = Date().timeIntervalSince1970
        clock.start()
        func step(_ position: Int) {
            if position < widths.count {
                window.setFrame(NSMakeRect(original.minX, original.minY, widths[position], original.height), display: true)
                Queue.mainQueue().after(1.0 / 30.0, {
                    step(position + 1)
                })
                return
            }
            clock.stop()
            window.setFrame(original, display: true)
            let end = self.processMonitor.snapshot()
            let elapsed = max(0.001, end.time - start.time)
            self.report.add(scenario: "resize", run: index, metrics: [
                "steps": Double(widths.count),
                "cpuCores": (end.cpuTime - start.cpuTime) / elapsed,
                "mainThreadBusyPercent": (end.mainThreadCpuTime - start.mainThreadCpuTime) / elapsed * 100,
                "mainMsPerStep": (end.mainThreadCpuTime - start.mainThreadCpuTime) * 1000 / Double(widths.count),
                "hitches": Double(clock.stats.hitches),
                "worstGapMs": clock.stats.worstGap * 1000,
                "rows": Double(table.count),
                "startUnixTime": startUnixTime,
                "endUnixTime": Date().timeIntervalSince1970
            ], notes: self.chatNotes)
            Queue.mainQueue().after(2.0, { [weak self] in
                self?.runResize(index: index + 1, completion: completion)
            })
        }
        step(0)
    }

    private func runSelection(index: Int, completion: @escaping () -> Void) {
        let runs = Int(self.configuration.double("-PerfLabRuns", 2.0))
        guard index < runs, let controller = self.controller else {
            completion()
            return
        }
        let table = controller.genericView.tableView
        var ids: [MessageId] = []
        let range = table.visibleRows()
        if range.length > 0 {
            for row in range.location ..< range.location + range.length {
                if let item = table.item(at: row) as? ChatRowItem, let id = item.message?.id {
                    ids.append(id)
                }
            }
        }
        let actions = 1 + ids.count * 2 + 1
        let clock = PerfLabFrameClock(view: table)
        let start = self.processMonitor.snapshot()
        let startUnixTime = Date().timeIntervalSince1970
        clock.start()
        func step(_ position: Int) {
            if position == 0 {
                controller.chatInteraction.update({ $0.withSelectionState() })
            } else if position <= ids.count * 2 {
                let id = ids[(position - 1) % ids.count]
                controller.chatInteraction.update({ $0.withToggledSelectedMessage(id) })
            } else {
                controller.chatInteraction.update({ $0.withoutSelectionState() })
            }
            if position + 1 < actions {
                Queue.mainQueue().after(1.0 / 20.0, {
                    step(position + 1)
                })
                return
            }
            Queue.mainQueue().after(0.5, { [weak self] in
                guard let self else {
                    return
                }
                clock.stop()
                let end = self.processMonitor.snapshot()
                let elapsed = max(0.001, end.time - start.time)
                self.report.add(scenario: "selection", run: index, metrics: [
                    "actions": Double(actions),
                    "cpuCores": (end.cpuTime - start.cpuTime) / elapsed,
                    "mainThreadBusyPercent": (end.mainThreadCpuTime - start.mainThreadCpuTime) / elapsed * 100,
                    "mainMsPerAction": (end.mainThreadCpuTime - start.mainThreadCpuTime) * 1000 / Double(actions),
                    "hitches": Double(clock.stats.hitches),
                    "worstGapMs": clock.stats.worstGap * 1000,
                    "startUnixTime": startUnixTime,
                    "endUnixTime": Date().timeIntervalSince1970
                ], notes: self.chatNotes)
                Queue.mainQueue().after(1.5, { [weak self] in
                    self?.runSelection(index: index + 1, completion: completion)
                })
            })
        }
        step(0)
    }

    private func runIdle(index: Int, completion: @escaping () -> Void) {
        let runs = Int(self.configuration.double("-PerfLabRuns", 2.0))
        guard index < runs, let table = self.controller?.genericView.tableView else {
            completion()
            return
        }
        let duration = self.configuration.double("-PerfLabIdleDuration", 10.0)
        let clock = PerfLabFrameClock(view: table)
        let start = self.processMonitor.snapshot()
        let startUnixTime = Date().timeIntervalSince1970
        clock.start()
        Queue.mainQueue().after(duration, { [weak self] in
            guard let self else {
                return
            }
            clock.stop()
            let end = self.processMonitor.snapshot()
            let elapsed = max(0.001, end.time - start.time)
            self.report.add(scenario: "idle", run: index, metrics: [
                "cpuCores": (end.cpuTime - start.cpuTime) / elapsed,
                "mainThreadBusyPercent": (end.mainThreadCpuTime - start.mainThreadCpuTime) / elapsed * 100,
                "hitches": Double(clock.stats.hitches),
                "footprintMB": Double(end.footprint) / 1048576.0,
                "startUnixTime": startUnixTime,
                "endUnixTime": Date().timeIntervalSince1970
            ], notes: self.chatNotes)
            self.runIdle(index: index + 1, completion: completion)
        })
    }

    private func runOpens(remaining: Int, index: Int, completion: @escaping () -> Void) {
        guard let peerId = self.openPeerId ?? self.controller?.chatInteraction.peerId else {
            completion()
            return
        }
        self.openPeerId = peerId
        if self.controller != nil {
            self.context.bindings.rootNavigation().back()
            self.controller = nil
            Queue.mainQueue().after(1.5, { [weak self] in
                self?.runOpens(remaining: remaining, index: index, completion: completion)
            })
            return
        }
        guard remaining > 0 else {
            let controller = self.makeChatController(context: self.context, peerId: peerId)
            self.controller = controller
            self.context.bindings.rootNavigation().push(controller)
            Queue.mainQueue().after(3.0, completion)
            return
        }
        let start = self.processMonitor.snapshot()
        let startUnixTime = Date().timeIntervalSince1970
        let startedAt = CACurrentMediaTime()
        let controller = self.makeChatController(context: self.context, peerId: peerId)
        self.context.bindings.rootNavigation().push(controller)
        var firstRowsAt: Double?
        func poll() {
            let elapsed = CACurrentMediaTime() - startedAt
            if firstRowsAt == nil, controller.genericView.tableView.count > 1 {
                firstRowsAt = elapsed
            }
            if elapsed < 2.0 {
                Queue.mainQueue().after(1.0 / 60.0, poll)
                return
            }
            let end = self.processMonitor.snapshot()
            let duration = max(0.001, end.time - start.time)
            self.report.add(scenario: "open", run: index, metrics: [
                "firstRowsSeconds": firstRowsAt ?? -1,
                "rows": Double(controller.genericView.tableView.count),
                "cpuSeconds": end.cpuTime - start.cpuTime,
                "cpuCores": (end.cpuTime - start.cpuTime) / duration,
                "mainThreadSeconds": end.mainThreadCpuTime - start.mainThreadCpuTime,
                "mainThreadBusyPercent": (end.mainThreadCpuTime - start.mainThreadCpuTime) / duration * 100,
                "footprintMB": Double(end.footprint) / 1048576.0,
                "startUnixTime": startUnixTime,
                "endUnixTime": Date().timeIntervalSince1970
            ], notes: self.chatNotes)
            self.context.bindings.rootNavigation().back()
            Queue.mainQueue().after(1.5, { [weak self] in
                self?.runOpens(remaining: remaining - 1, index: index + 1, completion: completion)
            })
        }
        poll()
    }

    private func waitForPinned(attempts: Int, completion: @escaping () -> Void) {
        if attempts <= 0 || self.controller?.chatInteraction.presentation.pinnedMessageId != nil {
            completion()
            return
        }
        Queue.mainQueue().after(0.25, { [weak self] in
            self?.waitForPinned(attempts: attempts - 1, completion: completion)
        })
    }

    private func runPinned(remaining: Int, completion: @escaping () -> Void) {
        guard remaining > 0, let controller = self.controller, let pinned = controller.chatInteraction.presentation.pinnedMessageId else {
            completion()
            return
        }
        let target = pinned.messageId
        self.navigate(name: "\(self.namePrefix)pinned", target: target, notes: self.chatNotes.merging(["pinnedIndex": "\(pinned.index)", "pinnedTotal": "\(pinned.totalCount)"], uniquingKeysWith: { $1 }), action: {
            controller.chatInteraction.focusPinnedMessageId(target)
        }, after: { [weak controller] in
            let next = controller?.chatInteraction.presentation.pinnedMessageId?.messageId
            return ["barAdvanced": next != nil && next != target ? 1.0 : 0.0, "barCleared": next == nil ? 1.0 : 0.0]
        }, completion: { [weak self] in
            self?.traceBar(ticks: 20, trace: [], completion: { [weak self] trace in
                self?.report.add(scenario: "\(self?.namePrefix ?? "")barTrace", run: 0, metrics: [:], notes: ["target": "\(target.id)", "trace": trace.joined(separator: ",")])
                self?.runPinned(remaining: remaining - 1, completion: completion)
            })
        })
    }

    private func traceBar(ticks: Int, trace: [String], completion: @escaping ([String]) -> Void) {
        var trace = trace
        let current = self.controller?.chatInteraction.presentation.pinnedMessageId.map { "\($0.messageId.id)" } ?? "nil"
        if trace.last != current {
            trace.append(current)
        }
        if ticks <= 0 {
            completion(trace)
            return
        }
        Queue.mainQueue().after(0.1, { [weak self] in
            self?.traceBar(ticks: ticks - 1, trace: trace, completion: completion)
        })
    }

    private func runJumps(targets: [MessageId], completion: @escaping () -> Void) {
        guard let target = targets.first, let controller = self.controller else {
            completion()
            return
        }
        let rest = Array(targets.dropFirst())
        controller.chatInteraction.scrollToLatest(true)
        Queue.mainQueue().after(2.0, { [weak self] in
            guard let self else {
                return
            }
            self.navigate(name: "\(self.namePrefix)jump", target: target, notes: self.chatNotes, action: {
                controller.chatInteraction.focusMessageId(nil, .init(messageId: target, string: nil), .CenterEmpty)
            }, completion: { [weak self] in
                Queue.mainQueue().after(1.0, {
                    self?.runJumps(targets: rest, completion: completion)
                })
            })
        })
    }

    private func rowRect(for messageId: MessageId) -> (rect: NSRect, visible: NSRect)? {
        guard let table = self.controller?.genericView.tableView else {
            return nil
        }
        let range = table.visibleRows()
        guard range.length > 0 else {
            return nil
        }
        let clip = table.clipView
        let presented = clip.layer?.presentation()?.bounds ?? clip.bounds
        for row in range.location ..< range.location + range.length {
            if let item = table.item(at: row) as? ChatRowItem, item.messages.contains(where: { $0.id == messageId }) {
                let rect = table.rectOf(index: row)
                guard rect.intersects(presented) else {
                    return nil
                }
                return (rect, presented)
            }
        }
        return nil
    }

    private func navigate(name: String, target: MessageId, notes: [String: String], action: () -> Void, after: (() -> [String: Double])? = nil, completion: @escaping () -> Void) {
        guard let table = self.controller?.genericView.tableView else {
            completion()
            return
        }
        self.navigationIndex += 1
        let index = self.navigationIndex
        var notes = notes
        notes["messageId"] = "\(target.id)"
        if Int(self.configuration.double("-PerfLabSampleNavigation", 0.0)) == index {
            let process = Process()
            process.launchPath = "/usr/bin/sample"
            process.arguments = ["\(ProcessInfo.processInfo.processIdentifier)", "3", "-file", self.configuration.outputDirectory.appendingPathComponent("chat-navigation-\(self.configuration.label)-nav\(index).sample.txt").path]
            try? process.run()
        }
        let wasVisibleBefore = self.rowRect(for: target) != nil
        let destinationAtStart = table.clipView.destination != nil
        let start = self.processMonitor.snapshot()
        let startUnixTime = Date().timeIntervalSince1970
        let startedAt = CACurrentMediaTime()
        let clock = PerfLabFrameClock(view: table)
        var coverageFrames = 0
        var blankFrames = 0
        var worstBlank: CGFloat = 0
        var travel: CGFloat = 0
        var lastPresentedY: CGFloat?
        var blankTrace: [String] = []
        var uncommittedFrames = 0
        var teleports = 0
        clock.onFrame = { [weak table] _ in
            guard let table, let rows = table.documentView as? NSTableView else {
                return
            }
            let clip = table.clipView
            let presented = clip.layer?.presentation()?.bounds ?? clip.bounds
            if abs(presented.minY - clip.bounds.minY) > clip.bounds.height * 1.5 {
                uncommittedFrames += 1
                return
            }
            if let lastPresentedY {
                let delta = abs(presented.minY - lastPresentedY)
                if delta > presented.height {
                    teleports += 1
                } else {
                    travel += delta
                }
            }
            lastPresentedY = presented.minY
            let range = rows.rows(in: presented)
            var blank: CGFloat = 0
            if range.length > 0 {
                for row in range.location ..< range.location + range.length {
                    if rows.rowView(atRow: row, makeIfNecessary: false) == nil {
                        blank += rows.rect(ofRow: row).intersection(presented).height
                    }
                }
            }
            coverageFrames += 1
            if blank > 0 {
                blankFrames += 1
                worstBlank = max(worstBlank, blank)
                if blankTrace.count < 6 {
                    let prepared = rows.preparedContentRect
                    let visible = rows.visibleRect
                    var available: [Int] = []
                    rows.enumerateAvailableRowViews { _, row in
                        available.append(row)
                    }
                    blankTrace.append("f\(coverageFrames) pres=\(Int(presented.minY))..\(Int(presented.maxY)) vis=\(Int(visible.minY))..\(Int(visible.maxY)) prep=\(Int(prepared.minY))..\(Int(prepared.maxY)) need=\(range.location)..<\(range.location + range.length) have=\(available.min() ?? -1)...\(available.max() ?? -1)#\(available.count) blank=\(Int(blank))")
                }
            }
        }
        clock.start()
        action()
        let timeout = self.configuration.double("-PerfLabNavigationTimeout", 8.0)
        var visibleAt: Double?
        var lastMinY: CGFloat?
        var stableTicks = 0
        func poll() {
            let now = CACurrentMediaTime()
            let elapsed = now - startedAt
            if let (rect, visible) = self.rowRect(for: target) {
                if visibleAt == nil {
                    visibleAt = elapsed
                }
                let offset = rect.minY - visible.minY
                if let lastMinY, abs(lastMinY - offset) < 0.5 {
                    stableTicks += 1
                } else {
                    stableTicks = 0
                }
                lastMinY = offset
                if stableTicks >= 6 && elapsed > 0.3 {
                    done(settledAt: elapsed, rect: rect, visible: visible)
                    return
                }
            } else {
                stableTicks = 0
                lastMinY = nil
            }
            if elapsed > timeout {
                done(settledAt: nil, rect: nil, visible: nil)
                return
            }
            Queue.mainQueue().after(1.0 / 60.0, poll)
        }
        func done(settledAt: Double?, rect: NSRect?, visible: NSRect?) {
            clock.stop()
            let end = self.processMonitor.snapshot()
            let duration = max(0.001, end.time - start.time)
            var metrics: [String: Double] = [
                "found": settledAt == nil ? 0.0 : 1.0,
                "visibleSeconds": visibleAt ?? -1.0,
                "settledSeconds": settledAt ?? -1.0,
                "wasVisibleBefore": wasVisibleBefore ? 1.0 : 0.0,
                "hitches": Double(clock.stats.hitches),
                "worstGapMs": clock.stats.worstGap * 1000,
                "cpuCores": (end.cpuTime - start.cpuTime) / duration,
                "mainThreadBusyPercent": (end.mainThreadCpuTime - start.mainThreadCpuTime) / duration * 100,
                "footprintMB": Double(end.footprint) / 1048576.0,
                "frames": Double(coverageFrames),
                "blankFrames": Double(blankFrames),
                "worstBlankPx": Double(worstBlank),
                "scrollTravelPx": Double(travel),
                "uncommittedFrames": Double(uncommittedFrames),
                "teleports": Double(teleports),
                "destinationAtStart": destinationAtStart ? 1.0 : 0.0,
                "windowKey": table.window?.isKeyWindow == true ? 1.0 : 0.0,
                "startUnixTime": startUnixTime,
                "endUnixTime": Date().timeIntervalSince1970
            ]
            if let after {
                for (key, value) in after() {
                    metrics[key] = value
                }
            }
            if let rect, let visible, visible.height > 0 {
                metrics["finalOffsetPx"] = rect.minY - visible.minY
                metrics["rowHeight"] = rect.height
                metrics["centerOffset"] = (rect.midY - visible.midY) / visible.height
                metrics["fullyVisible"] = visible.contains(rect) || rect.height > visible.height ? 1.0 : 0.0
            }
            if !blankTrace.isEmpty {
                notes["blankTrace"] = blankTrace.joined(separator: " | ")
            }
            self.report.add(scenario: "\(name)-\(index)", run: 0, metrics: metrics, notes: notes)
            completion()
        }
        poll()
    }

    private func startSweep() {
        let context = self.context
        let maxChats = Int(self.configuration.double("-PerfLabMaxChats", 8.0))
        let candidates: Signal<[(PeerId, String)], NoError> = context.engine.messages.chatList(group: .root, count: 80)
        |> take(1)
        |> map { chatList -> [(PeerId, String)] in
            var result: [(PeerId, String)] = []
            for item in chatList.items.reversed() {
                guard case let .chatList(peerId) = item.id, item.readCounters?.isUnread != true, (item.readCounters?.count ?? 0) == 0, let peer = item.renderedPeer.peer else {
                    continue
                }
                if case let .channel(channel) = peer, !channel.flags.contains(.isForum) {
                    result.append((peerId, peer.debugDisplayTitle))
                } else if case .legacyGroup = peer {
                    result.append((peerId, peer.debugDisplayTitle))
                }
            }
            return result
        }
        self.loadDisposable = (candidates |> deliverOnMainQueue).start(next: { [weak self] candidates in
            NSLog("ChatNavigationLab: %d read channels/groups", candidates.count)
            self?.sweep(candidates: candidates, chatsWithPins: 0, maxChats: maxChats)
        })
    }

    private func sweep(candidates: [(PeerId, String)], chatsWithPins: Int, maxChats: Int) {
        guard chatsWithPins < maxChats, let (peerId, title) = candidates.first else {
            self.finish()
            return
        }
        let rest = Array(candidates.dropFirst())
        let pinnedSignal = self.context.engine.messages.searchMessages(location: .peer(peerId: peerId, fromId: nil, tags: .pinned, reactions: nil, threadId: nil, minDate: nil, maxDate: nil), query: "", state: nil, limit: 20)
        |> map { $0.0.messages.map { $0.id } }
        |> take(1)
        |> timeout(10.0, queue: Queue.mainQueue(), alternate: .single([]))
        self.loadDisposable = (pinnedSignal |> deliverOnMainQueue).start(next: { [weak self] pinnedIds in
            guard let self else {
                return
            }
            guard !pinnedIds.isEmpty else {
                self.sweep(candidates: rest, chatsWithPins: chatsWithPins, maxChats: maxChats)
                return
            }
            let chatIndex = chatsWithPins
            self.namePrefix = "c\(chatIndex)-"
            self.chatNotes = ["chat": title, "pins": "\(pinnedIds.count)"]
            let controller = self.makeChatController(context: self.context, peerId: peerId)
            self.controller = controller
            self.context.bindings.rootNavigation().push(controller)
            Queue.mainQueue().after(self.configuration.double("-PerfLabOpenWait", 4.0), {
                self.runPinned(remaining: min(pinnedIds.count + 1, 6), completion: {
                    self.runJumps(targets: Array(pinnedIds.prefix(4)), completion: {
                        self.context.bindings.rootNavigation().back()
                        self.controller = nil
                        Queue.mainQueue().after(1.5, {
                            self.sweep(candidates: rest, chatsWithPins: chatsWithPins + 1, maxChats: maxChats)
                        })
                    })
                })
            })
        })
    }
}
#endif
