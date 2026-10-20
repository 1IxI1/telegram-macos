import Cocoa
import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
#if SHARE
import TelegramThemeShare
import TelegramContextShare
#else
import TelegramTheme
import TelegramContext
#endif

public final class MessageReadMetricsManager {

    public struct VisibleMessageInfo {
        public let messageId: MessageId
        public let itemHeight: CGFloat
        public let visibleRect: NSRect
        public let viewportHeight: CGFloat
        public init(messageId: MessageId, itemHeight: CGFloat, visibleRect: NSRect, viewportHeight: CGFloat) {
            self.messageId = messageId
            self.itemHeight = itemHeight
            self.visibleRect = visibleRect
            self.viewportHeight = viewportHeight
        }
    }

    private struct MessageTrackingState {
        public let viewId: Int64
        public let messageId: MessageId
        public var startTime: CFAbsoluteTime
        public var accumulatedTimeMs: Int
        public var accumulatedActiveTimeMs: Int
        public var lastTickTime: CFAbsoluteTime
        public var postHeight: CGFloat
        public var viewportHeight: CGFloat
        public var seenTop: CGFloat
        public var seenBottom: CGFloat
        public var confirmed: Bool
        public var startGraceTimer: SwiftSignalKit.Timer?
        public var endGraceTimer: SwiftSignalKit.Timer?
    }

    private let context: any AccountContextProtocol
    private let peerId: PeerId

    private var trackingStates: [MessageId: MessageTrackingState] = [:]
    private var pendingMetrics: [TelegramMessageReadMetric] = []

    private var batchTimer: SwiftSignalKit.Timer?
    private var tickTimer: SwiftSignalKit.Timer?
    private let reportDisposable = MetaDisposable()

    private var lastUserActivityTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private let userActivityTimeout: CFAbsoluteTime = 15.0
    private var isGloballyPaused: Bool = false

    private var isUserActive: Bool {
        return CFAbsoluteTimeGetCurrent() - lastUserActivityTime < userActivityTimeout
    }

    public init(context: any AccountContextProtocol, peerId: PeerId) {
        self.context = context
        self.peerId = peerId
    }

    deinit {
        tickTimer?.invalidate()
        batchTimer?.invalidate()
        reportDisposable.dispose()
        for (_, state) in trackingStates {
            state.startGraceTimer?.invalidate()
            state.endGraceTimer?.invalidate()
        }
    }

    public func updateVisibleMessages(_ messages: [VisibleMessageInfo]) {
        let currentIds = Set(messages.map { $0.messageId })

        for info in messages {
            if var state = trackingStates[info.messageId] {
                if state.endGraceTimer != nil {
                    state.endGraceTimer?.invalidate()
                    state.endGraceTimer = nil
                }
                state.seenTop = min(state.seenTop, info.visibleRect.minY)
                state.seenBottom = max(state.seenBottom, info.visibleRect.maxY)
                trackingStates[info.messageId] = state
            } else {
                beginTracking(info)
            }
        }

        for (messageId, state) in trackingStates {
            if !currentIds.contains(messageId) && state.endGraceTimer == nil {
                startEndGrace(for: messageId)
            }
        }
    }

    public func recordUserActivity() {
        lastUserActivityTime = CFAbsoluteTimeGetCurrent()
    }

    public func pause() {
        guard !isGloballyPaused else { return }
        isGloballyPaused = true
        let now = CFAbsoluteTimeGetCurrent()
        for (id, var state) in trackingStates {
            if state.confirmed {
                let elapsed = now - state.lastTickTime
                state.accumulatedTimeMs += Int(elapsed * 1000)
                if isUserActive {
                    state.accumulatedActiveTimeMs += Int(elapsed * 1000)
                }
                state.lastTickTime = now
                trackingStates[id] = state
            }
        }
        tickTimer?.invalidate()
        tickTimer = nil
    }

    public func resume() {
        guard isGloballyPaused else { return }
        isGloballyPaused = false
        let now = CFAbsoluteTimeGetCurrent()
        for (id, var state) in trackingStates {
            if state.confirmed {
                state.lastTickTime = now
                trackingStates[id] = state
            }
        }
        ensureTickTimer()
    }

    public func finalizeAll() {
        let ids = Array(trackingStates.keys)
        for id in ids {
            finalizeTracking(messageId: id)
        }
        flushBatch()
    }

    private func beginTracking(_ info: VisibleMessageInfo) {
        let messageId = info.messageId
        var state = MessageTrackingState(
            viewId: Int64.random(in: Int64.min...Int64.max),
            messageId: messageId,
            startTime: 0,
            accumulatedTimeMs: 0,
            accumulatedActiveTimeMs: 0,
            lastTickTime: 0,
            postHeight: info.itemHeight,
            viewportHeight: info.viewportHeight,
            seenTop: info.visibleRect.minY,
            seenBottom: info.visibleRect.maxY,
            confirmed: false,
            startGraceTimer: nil,
            endGraceTimer: nil
        )

        let timer = SwiftSignalKit.Timer(timeout: 0.3, repeat: false, completion: { [weak self] in
            self?.confirmTracking(messageId: messageId)
        }, queue: .mainQueue())
        state.startGraceTimer = timer
        trackingStates[messageId] = state
        timer.start()
    }

    private func confirmTracking(messageId: MessageId) {
        guard var state = trackingStates[messageId], !state.confirmed else { return }
        let now = CFAbsoluteTimeGetCurrent()
        state.confirmed = true
        state.startTime = now
        state.lastTickTime = now
        state.startGraceTimer = nil
        trackingStates[messageId] = state
        ensureTickTimer()
    }

    private func startEndGrace(for messageId: MessageId) {
        guard var state = trackingStates[messageId] else { return }
        if !state.confirmed {
            state.startGraceTimer?.invalidate()
            trackingStates.removeValue(forKey: messageId)
            cleanupTickTimerIfNeeded()
            return
        }
        let timer = SwiftSignalKit.Timer(timeout: 0.3, repeat: false, completion: { [weak self] in
            self?.finalizeTracking(messageId: messageId)
        }, queue: .mainQueue())
        state.endGraceTimer = timer
        trackingStates[messageId] = state
        timer.start()
    }

    private func finalizeTracking(messageId: MessageId) {
        guard var state = trackingStates[messageId] else { return }
        state.startGraceTimer?.invalidate()
        state.endGraceTimer?.invalidate()

        if state.confirmed {
            if !isGloballyPaused {
                let now = CFAbsoluteTimeGetCurrent()
                let elapsed = now - state.lastTickTime
                state.accumulatedTimeMs += Int(elapsed * 1000)
                if isUserActive {
                    state.accumulatedActiveTimeMs += Int(elapsed * 1000)
                }
            }

            if state.accumulatedTimeMs >= 300 {
                let heightToViewportRatio = state.viewportHeight > 0 ? Double(state.postHeight) / Double(state.viewportHeight) : 0
                let seenRangeRatio: Double
                if state.postHeight > 0 {
                    seenRangeRatio = min(max(Double(state.seenBottom - state.seenTop) / Double(state.postHeight), 0), 1)
                } else {
                    seenRangeRatio = 0
                }

                let metric = TelegramMessageReadMetric(
                    id: state.viewId,
                    messageId: state.messageId,
                    timeInViewMs: state.accumulatedTimeMs,
                    activeTimeInViewMs: state.accumulatedActiveTimeMs,
                    heightToViewportRatio: heightToViewportRatio,
                    seenRangeRatio: seenRangeRatio
                )
                pendingMetrics.append(metric)
                scheduleBatch()
            }
        }

        trackingStates.removeValue(forKey: messageId)
        cleanupTickTimerIfNeeded()
    }

    private func tick() {
        guard !isGloballyPaused else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let active = isUserActive

        var toFinalize: [MessageId] = []

        for (id, var state) in trackingStates {
            guard state.confirmed else { continue }
            let elapsed = now - state.lastTickTime
            state.accumulatedTimeMs += Int(elapsed * 1000)
            if active {
                state.accumulatedActiveTimeMs += Int(elapsed * 1000)
            }
            state.lastTickTime = now
            trackingStates[id] = state

            if now - state.startTime >= 300 {
                toFinalize.append(id)
            }
        }

        for id in toFinalize {
            finalizeTracking(messageId: id)
        }
    }

    private func ensureTickTimer() {
        guard tickTimer == nil, !isGloballyPaused else { return }
        let hasConfirmed = trackingStates.values.contains(where: { $0.confirmed })
        guard hasConfirmed else { return }

        let timer = SwiftSignalKit.Timer(timeout: 0.2, repeat: true, completion: { [weak self] in
            self?.tick()
        }, queue: .mainQueue())
        tickTimer = timer
        timer.start()
    }

    private func cleanupTickTimerIfNeeded() {
        let hasConfirmed = trackingStates.values.contains(where: { $0.confirmed })
        if !hasConfirmed {
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    private func scheduleBatch() {
        guard batchTimer == nil else { return }
        let timer = SwiftSignalKit.Timer(timeout: 2.0, repeat: false, completion: { [weak self] in
            self?.flushBatch()
        }, queue: .mainQueue())
        batchTimer = timer
        timer.start()
    }

    private func flushBatch() {
        batchTimer?.invalidate()
        batchTimer = nil

        guard !pendingMetrics.isEmpty else { return }
        let metrics = pendingMetrics
        pendingMetrics.removeAll()

        reportDisposable.set(
            context.engine.messages.reportPeerReadMetrics(
                peerId: peerId,
                metrics: metrics
            ).start()
        )
    }
}
