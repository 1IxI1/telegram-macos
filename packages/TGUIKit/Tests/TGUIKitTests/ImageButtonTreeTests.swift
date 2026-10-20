import XCTest
import AppKit
@testable import TGUIKit

final class ImageButtonTreeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private func makeButton() -> ImageButton {
        let button = ImageButton()
        button.set(image: testImage(CGSize(width: 40, height: 40)), for: .Normal)
        _ = button.sizeToFit(.zero, NSMakeSize(40, 40), thatFit: true)
        return button
    }

    func testPlainButtonHoldsOnlyItsImage() {
        let button = makeButton()
        XCTAssertEqual(button.subviews.count, 1)
        XCTAssertTrue(button.subviews.first === button.imageView)
    }

    func testClearBackgroundKeepsThePlateDetached() {
        let button = makeButton()
        button.set(additionBackgroundColor: .clear, for: .Normal)
        XCTAssertEqual(button.subviews.count, 1)
        XCTAssertNil(button.additionBackgroundView.superview)
    }

    func testColoredBackgroundAttachesThePlateBelowTheImage() {
        let button = makeButton()
        button.set(additionBackgroundColor: .red, for: .Normal)
        XCTAssertEqual(button.subviews.count, 2)
        XCTAssertTrue(button.subviews.first === button.additionBackgroundView)
        XCTAssertTrue(button.subviews.last === button.imageView)
        XCTAssertEqual(button.additionBackgroundView.frame, button.bounds)
    }

    func testPlateAttachesBelowTheGlass() {
        let button = makeButton()
        button.setGlassEffect(size: NSMakeSize(40, 40))
        button.set(additionBackgroundColor: .red, for: .Normal)
        XCTAssertEqual(viewClassNames(button.subviews), ["View", "LiquidGlassView", "ImageView"])
        XCTAssertTrue(button.subviews.first === button.additionBackgroundView)
    }

    func testPlateAttachesAboveTheBlurBackground() {
        let button = makeButton()
        button.blurBackground = .white
        button.set(additionBackgroundColor: .red, for: .Normal)
        XCTAssertEqual(viewClassNames(button.subviews), ["VisualEffect", "View", "ImageView"])
    }

    func testHoverOnlyBackgroundAttachesOnHover() {
        let button = makeButton()
        button.set(additionBackgroundColor: .red, for: .Hover)
        XCTAssertNil(button.additionBackgroundView.superview)
        button.apply(state: .Hover)
        XCTAssertTrue(button.subviews.first === button.additionBackgroundView)
    }

    func testTextButtonHoldsNoPlate() {
        let button = TextButton()
        button.set(text: "Done", for: .Normal)
        XCTAssertEqual(viewClassNames(button.subviews), ["ImageView", "TextView"])
    }
}

func viewClassNames(_ views: [NSView]) -> [String] {
    return views.map { String(describing: type(of: $0)) }
}
