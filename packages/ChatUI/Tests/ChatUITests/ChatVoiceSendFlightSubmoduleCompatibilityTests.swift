import XCTest
import Cocoa
@testable import ChatUI

final class ChatVoiceSendFlightSubmoduleCompatibilityTests: XCTestCase {
    private static let transitionPath = "submodules/telegram-ios/submodules/TelegramUI/Sources/ChatMessageTransitionNode.swift"
    private static let recordingButtonPath = "submodules/telegram-ios/submodules/TelegramUI/Components/ChatTextInputMediaRecordingButton/Sources/ChatTextInputMediaRecordingButton.swift"
    private static let bubblePath = "submodules/telegram-ios/submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift"

    private func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        return try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func numbers(in path: String, _ pattern: String) throws -> [Double] {
        let text = try source(path)
        let regex = try NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            XCTFail("\(path) does not match \(pattern)")
            return []
        }
        return (1 ..< match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).flatMap { Double(text[$0]) }
        }
    }

    private func controlPoints(of function: CAMediaTimingFunction) -> [Float] {
        var result: [Float] = []
        for index in 1 ... 2 {
            var point: [Float] = [0, 0]
            function.getControlPoint(at: index, values: &point)
            result.append(contentsOf: point)
        }
        return result
    }

    func testDurationAndCurvesMatchSubmodule() throws {
        let duration = try numbers(in: Self.transitionPath, "private func chatMessageTransitionAnimationDuration\\(\\) -> Double \\{ #if DEBUG && false return [0-9.]+ #else return ([0-9.]+) #endif")
        XCTAssertEqual(duration, [ChatVoiceSendFlightMotion.duration])

        let vertical = try numbers(in: Self.transitionPath, "verticalAnimationControlPoints: \\(Float, Float, Float, Float\\) = \\(([0-9.]+), ([0-9.]+), ([0-9.]+), ([0-9.]+)\\)")
        let actualVertical = ChatVoiceSendFlightMotion.verticalControlPoints
        XCTAssertEqual(vertical.map { Float($0) }, [actualVertical.0, actualVertical.1, actualVertical.2, actualVertical.3])

        let horizontal = try numbers(in: Self.transitionPath, "horizontalAnimationCurve: ContainedViewLayoutTransitionCurve = \\.custom\\(([0-9.]+), ([0-9.]+), ([0-9.]+), ([0-9.]+)\\)")
        let actualHorizontal = ChatVoiceSendFlightMotion.horizontalControlPoints
        XCTAssertEqual(horizontal.map { Float($0) }, [actualHorizontal.0, actualHorizontal.1, actualHorizontal.2, actualHorizontal.3])

        XCTAssertEqual(controlPoints(of: ChatVoiceSendFlightMotion.timingFunction(actualVertical)), [actualVertical.0, actualVertical.1, actualVertical.2, actualVertical.3])
        XCTAssertEqual(controlPoints(of: ChatVoiceSendFlightMotion.timingFunction(actualHorizontal)), [actualHorizontal.0, actualHorizontal.1, actualHorizontal.2, actualHorizontal.3])

        let delay = try numbers(in: Self.transitionPath, "let horizontalDuration: Double = verticalDuration let delay: Double = ([0-9.]+)")
        XCTAssertEqual(delay, [0.0])
    }

    func testBothAxesUseTheirOwnCurveInSubmodule() throws {
        let transition = try source(Self.transitionPath)
        XCTAssertTrue(transition.contains("let _ = audioMicInput.micButton.animateDecorationToSentMessage(targetRect: targetAbsoluteRect, in: self.view, duration: verticalDuration, horizontalCurve: ChatMessageTransitionNodeImpl.horizontalAnimationCurve, verticalCurve: ChatMessageTransitionNodeImpl.verticalAnimationCurve)"))
        XCTAssertTrue(transition.contains("self.containerNode.layer.animatePosition(from: CGPoint(x: 0.0, y: sourceAbsoluteRect.midY - targetAbsoluteRect.midY), to: CGPoint(), duration: verticalDuration, delay: delay, mediaTimingFunction: ChatMessageTransitionNodeImpl.verticalAnimationCurve.mediaTimingFunction, additive: true, force: true, completion: { [weak self, weak contextContainer] _ in"))
        XCTAssertTrue(transition.contains("self.containerNode.layer.animatePosition(from: CGPoint(x: sourceAbsoluteRect.midX - targetAbsoluteRect.midX, y: 0.0), to: CGPoint(), duration: horizontalDuration, delay: delay, mediaTimingFunction: ChatMessageTransitionNodeImpl.horizontalAnimationCurve.mediaTimingFunction, additive: true)"))

        let button = try source(Self.recordingButtonPath)
        XCTAssertTrue(button.contains("decoration.layer.animatePosition(from: CGPoint(x: fromPosition.x - toPosition.x, y: 0.0), to: CGPoint(), duration: duration, mediaTimingFunction: horizontalCurve.mediaTimingFunction, additive: true)"))
        XCTAssertTrue(button.contains("decoration.layer.animatePosition(from: CGPoint(x: 0.0, y: fromPosition.y - toPosition.y), to: CGPoint(), duration: duration, mediaTimingFunction: verticalCurve.mediaTimingFunction, additive: true)"))
        XCTAssertTrue(button.contains("decoration.layer.animateScale(from: fromScale, to: toScale, duration: duration, mediaTimingFunction: verticalCurve.mediaTimingFunction)"))
    }

    func testFadesMatchSubmodule() throws {
        let button = try source(Self.recordingButtonPath)
        XCTAssertTrue(button.contains("let fadeDuration = min(0.06, duration)"))
        XCTAssertTrue(button.contains("decoration.layer.allowsGroupOpacity = true decoration.layer.animateAlpha(from: 1.0, to: 0.0, duration: fadeDuration, removeOnCompletion: false"))
        let bubble = try source(Self.bubblePath)
        XCTAssertTrue(bubble.contains("statusContainerNode.contentNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.06)"))
        XCTAssertEqual(ChatVoiceSendFlightMotion.fadeDuration, 0.06)
        XCTAssertEqual(min(ChatVoiceSendFlightMotion.fadeDuration, ChatVoiceSendFlightMotion.duration), 0.06)
    }

    func testScalesMatchSubmodule() throws {
        let button = try source(Self.recordingButtonPath)
        XCTAssertTrue(button.contains("let centreDiameter = decoration.bounds.width * CGFloat(ChatRecordingBlobAppearance.centreScale)"))
        XCTAssertTrue(button.contains("let toScale = target.width / centreDiameter"))
        XCTAssertTrue(button.contains("let diameter = decoration.bounds.width * CGFloat(ChatRecordingBlobAppearance.centreScale) return (decoration, CGSize(width: diameter, height: diameter).centered(in: decoration.bounds))"))
        let bubble = try source(Self.bubblePath)
        XCTAssertTrue(bubble.contains("transition.vertical.animateTransformScale(node: statusContainerNode.contentNode, from: sourceSize.width / statusContainerNode.contentRect.width)"))

        let submoduleToScale: (CGFloat, CGFloat) -> CGFloat = { targetWidth, centreDiameter in targetWidth / centreDiameter }
        let submoduleFromScale: (CGFloat, CGFloat) -> CGFloat = { sourceWidth, contentWidth in sourceWidth / contentWidth }
        for (centre, target) in [(CGFloat(60), CGFloat(40)), (40, 40), (99, 44)] {
            XCTAssertEqual(ChatVoiceSendFlightMotion.blobScale(targetWidth: target, centreDiameter: centre), submoduleToScale(target, centre))
            XCTAssertEqual(ChatVoiceSendFlightMotion.buttonScale(sourceWidth: centre, targetWidth: target), submoduleFromScale(centre, target))
        }
    }

    func testScaleTransformKeepsTheCentre() {
        let size = NSMakeSize(100, 40)
        for scale: CGFloat in [0.1, 0.4, 1.0, 1.5, 2.25] {
            let transform = CATransform3DGetAffineTransform(ChatVoiceSendFlightMotion.scaleTransform(scale, size: size))
            let centre = CGPoint(x: 50, y: 20).applying(transform)
            XCTAssertEqual(centre.x, 50, accuracy: 1e-9)
            XCTAssertEqual(centre.y, 20, accuracy: 1e-9)
            let corner = CGPoint(x: 100, y: 40).applying(transform)
            XCTAssertEqual(corner.x, 50 + 50 * scale, accuracy: 1e-9)
            XCTAssertEqual(corner.y, 20 + 20 * scale, accuracy: 1e-9)
        }
        XCTAssertTrue(CATransform3DIsIdentity(ChatVoiceSendFlightMotion.scaleTransform(1.0, size: size)))
    }

    func testMacFlightUsesTheSubmoduleTiming() throws {
        let flight = try source("packages/ChatUI/Sources/ChatUI/ChatVoiceSendFlight.swift")
        XCTAssertEqual(flight.components(separatedBy: "timingFunction: horizontalCurve, additive: true").count - 1, 2)
        XCTAssertEqual(flight.components(separatedBy: "timingFunction: verticalCurve, additive: true").count - 1, 2)
        XCTAssertEqual(flight.components(separatedBy: "timingFunction: verticalCurve, additive: false").count - 1, 2)
        XCTAssertTrue(flight.contains("duration: min(ChatVoiceSendFlightMotion.fadeDuration, duration)"))
        XCTAssertTrue(flight.contains("layer.allowsGroupOpacity = true layer.opacity = 0"))
        XCTAssertTrue(flight.contains("from: 0.0 as NSNumber, to: 1.0 as NSNumber, duration: ChatVoiceSendFlightMotion.fadeDuration, timingFunction: CAMediaTimingFunction(name: .easeInEaseOut)"))
        XCTAssertTrue(flight.contains("NSAnimationContext.beginGrouping() NSAnimationContext.current.duration = 0 NSAnimationContext.current.timingFunction = nil NSAnimationContext.current.allowsImplicitAnimation = false if !self.start(overlay: pending.overlay, target: target, tableView: tableView) {"))
        XCTAssertTrue(flight.contains("NSAnimationContext.endGrouping() }"))
    }
}
