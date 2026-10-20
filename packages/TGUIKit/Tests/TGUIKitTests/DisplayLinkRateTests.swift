import XCTest
import AppKit
import CoreVideo
@testable import TGUIKit

final class DisplayLinkRateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private var refreshRate: Double {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithCGDisplay(CGMainDisplayID(), &link)
        let period = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link!)
        return Double(period.timeScale) / Double(period.timeValue)
    }

    func testValueAnimatorTicksAtTheDisplayRate() {
        let finished = expectation(description: "finished")
        var ticks = 0
        var values: [CGFloat] = []
        let animator = DisplayLinkAnimator(duration: 1.0, from: 0, to: 1, update: { value in
            ticks += 1
            values.append(value)
        }, completion: {
            finished.fulfill()
        })
        wait(for: [finished], timeout: 4)
        withExtendedLifetime(animator) {}
        XCTAssertGreaterThan(Double(ticks), self.refreshRate * 0.8, "refresh \(self.refreshRate)")
        XCTAssertEqual(values.last, 1)
        XCTAssertEqual(values, values.sorted())
    }

    func testDisplayRateConstantAnimatorReportsTheFrameDuration() {
        var durations: [CGFloat] = []
        let animator = ConstantDisplayLinkAnimator(framesPerSecond: .max, update: { duration in
            durations.append(duration)
        })
        animator.isPaused = false
        let done = expectation(description: "done")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
        animator.isPaused = true
        XCTAssertGreaterThan(Double(durations.count), self.refreshRate * 0.8, "refresh \(self.refreshRate)")
        let median = durations.sorted()[durations.count / 2]
        XCTAssertEqual(Double(median), 1.0 / self.refreshRate, accuracy: 0.002)
    }

    func testDefaultConstantAnimatorKeepsSixtyFramesPerSecond() {
        var ticks = 0
        let animator = ConstantDisplayLinkAnimator(update: {
            ticks += 1
        })
        animator.isPaused = false
        let done = expectation(description: "done")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
        animator.isPaused = true
        XCTAssertEqual(Double(ticks), min(60, self.refreshRate), accuracy: 8)
    }
}

final class FrameStepTests: XCTestCase {
    func testSixtyHertzStepsAreUnchanged() {
        XCTAssertEqual(FrameStep.scale(1.0 / 60.0), 1, accuracy: 1e-9)
        XCTAssertEqual(FrameStep.decay(0.9, 1.0 / 60.0), 0.9, accuracy: 1e-9)
        XCTAssertEqual(FrameStep.blend(0.1, 1.0 / 60.0), 0.1, accuracy: 1e-9)
    }

    func testTwoHalfFramesMatchOneFrame() {
        let half: CGFloat = 1.0 / 120.0
        var smoothed: CGFloat = 0
        var target: CGFloat = 1
        for _ in 0 ..< 2 {
            smoothed = smoothed * FrameStep.decay(0.9, half) + target * (1 - FrameStep.decay(0.9, half))
        }
        XCTAssertEqual(smoothed, 0.1, accuracy: 1e-9)
        var chased: CGFloat = 0
        for _ in 0 ..< 2 {
            chased += (target - chased) * FrameStep.blend(0.2, half)
        }
        XCTAssertEqual(chased, 0.2, accuracy: 1e-9)
        target = 0
        XCTAssertEqual(FrameStep.scale(half) * 2, FrameStep.scale(1.0 / 60.0), accuracy: 1e-9)
    }
}
