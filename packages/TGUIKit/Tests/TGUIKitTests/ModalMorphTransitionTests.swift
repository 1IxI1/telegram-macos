import XCTest
import AppKit
import QuartzCore
@testable import TGUIKit

final class ModalMorphTransitionTests: XCTestCase {
    private var savedReduceMotion: (() -> Bool)!

    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
        savedReduceMotion = ModalMorphTransition.reduceMotion
        ModalMorphTransition.reduceMotion = { false }
    }

    override func tearDown() {
        ModalMorphTransition.reduceMotion = savedReduceMotion
        super.tearDown()
    }

    private let control = NSMakeRect(40, 40, 40, 40)
    private let modal = NSMakeRect(300, 200, 420, 520)

    private func dummyImage() -> CGImage {
        let ctx = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor.red.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return ctx.makeImage()!
    }

    func testChannelStartsAtFromAndSettlesOnTarget() {
        let channel = ModalMorphTransition.Channel(from: 40, to: 420, spring: .openWidth, tolerance: ModalMorphTransition.geometryTolerance)
        XCTAssertEqual(channel.value(at: 0), 40, accuracy: 0.5, "a channel starts at its from value")
        XCTAssertEqual(channel.value(at: ModalMorphTransition.maximumDuration), 420, accuracy: 1.0, "and settles on its to value")
    }

    func testUnderdampedSpringOvershoots() {
        // An underdamped spring's remaining must dip below zero (the value bounces past the target).
        var sawNegative = false
        var t = 0.0
        while t <= 1 {
            if ModalMorphTransition.Spring.openWidth.remaining(at: t) < -0.001 { sawNegative = true; break }
            t += 0.005
        }
        XCTAssertTrue(sawNegative, "open width spring should overshoot (bounce)")
    }

    func testCriticallyDampedSpringNeverOvershoots() {
        var t = 0.0
        while t <= 1.5 {
            XCTAssertGreaterThanOrEqual(ModalMorphTransition.Spring.openFade.remaining(at: t), -1e-6, "critically damped fade must not overshoot")
            t += 0.01
        }
    }

    func testSettlingTimeIsPositiveAndBounded() {
        let channel = ModalMorphTransition.Channel(from: 0, to: 1, spring: .openPosition, tolerance: ModalMorphTransition.unitTolerance)
        let settling = channel.settlingTime
        XCTAssertGreaterThan(settling, 0.1, "the morph takes a visible amount of time")
        XCTAssertLessThanOrEqual(settling, ModalMorphTransition.maximumDuration, "but is bounded")
    }

    func testSmoothstepClamps() {
        XCTAssertEqual(ModalMorphTransition.smoothstep(0, 1, -5), 0)
        XCTAssertEqual(ModalMorphTransition.smoothstep(0, 1, 5), 1)
        XCTAssertEqual(ModalMorphTransition.smoothstep(0, 1, 0.5), 0.5, accuracy: 0.0001)
    }

    func testReduceMotionSkipsTheMorphAndCallsCompletion() {
        ModalMorphTransition.reduceMotion = { true }
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 800, 800), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = View(frame: NSMakeRect(0, 0, 800, 800))
        window.contentView?.addSubview(host)
        var completed = false
        let transition = ModalMorphTransition.open(host: host, realView: nil, liveContent: nil, controlImage: nil, modalImage: dummyImage(), backgroundColor: nil, cornerRadius: 10, controlCornerRadius: 20, from: control, to: modal, completion: { completed = true })
        XCTAssertNil(transition, "reduce motion must skip the morph")
        XCTAssertTrue(completed, "completion still fires so the modal appears")
    }

    func testOpenAddsBubbleHidesRealViewAndRestoresOnCancel() {
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 800, 800), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = View(frame: NSMakeRect(0, 0, 800, 800))
        window.contentView?.addSubview(host)
        let realView = View(frame: modal)
        host.addSubview(realView)
        let transition = ModalMorphTransition.open(host: host, realView: realView, liveContent: nil, controlImage: dummyImage(), modalImage: dummyImage(), backgroundColor: nil, cornerRadius: 10, controlCornerRadius: 20, from: control, to: modal, completion: {})
        XCTAssertNotNil(transition)
        XCTAssertTrue(realView.isHidden, "the real modal is hidden while the morph plays")
        XCTAssertEqual(host.subviews.count, 3, "a bubble and a shadow view are added above the real view")
        let bubbleView = host.subviews.last
        XCTAssertNotNil(bubbleView?.layer?.animation(forKey: "modalMorph.position"))
        transition?.cancel()
        XCTAssertFalse(realView.isHidden, "the real modal is restored after the morph")
        XCTAssertEqual(host.subviews.count, 1, "the bubble and shadow views are removed after the morph")
    }
}
