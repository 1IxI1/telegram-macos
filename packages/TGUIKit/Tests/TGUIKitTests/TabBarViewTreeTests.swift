import XCTest
import AppKit
@testable import TGUIKit

private final class TestBadgeNode: Node {
    init() {
        let view = View(frame: NSMakeRect(0, 0, 10, 10))
        view.backgroundColor = .systemRed
        super.init(view)
    }

    override func update() {
        if let view = self.view, let superview = view.superview {
            view.setFrameOrigin(NSMakePoint(floor(superview.frame.width / 2) + 4, 4))
        }
    }
}

final class TabBarViewTreeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private func image(_ size: CGSize, _ color: NSColor) -> CGImage {
        let context = CGContext(data: nil, width: Int(size.width * 2), height: Int(size.height * 2), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: 0, y: 0, width: size.width * 2, height: size.height * 2))
        return context.makeImage()!
    }

    private func makeTab(_ size: CGSize, badge: Bool = false) -> TabItem {
        return TabItem(image: image(size, .systemGray), selectedImage: image(size, .systemBlue), controller: ViewController(), subNode: badge ? TestBadgeNode() : nil)
    }

    private func makeBar(width: CGFloat = 333, selected: Int = 0) -> TabBarView {
        let bar = TabBarView(frame: NSMakeRect(0, 0, width, 50))
        bar.addTab(makeTab(CGSize(width: 21, height: 23)))
        bar.addTab(makeTab(CGSize(width: 30, height: 30)))
        bar.addTab(makeTab(CGSize(width: 25, height: 19), badge: true))
        bar.addTab(makeTab(CGSize(width: 17, height: 26)))
        bar.setSelectedIndex(selected, respondToDelegate: false, animated: false)
        return bar
    }

    private func wrapLikeBefore(_ bar: TabBarView) {
        for control in bar.subviews {
            let icon = control.subviews[0]
            let container = View(frame: control.bounds)
            icon.removeFromSuperview()
            container.addSubview(icon)
            container.backgroundColor = .clear
            container.setFrameSize(NSMakeSize(NSWidth(icon.frame), NSHeight(container.frame)))
            control.addSubview(container, positioned: .below, relativeTo: control.subviews.first)
            icon.center()
            container.center()
        }
        bar.setFrameSize(bar.frame.size)
    }

    func testEachTabHoldsItsIconDirectly() {
        let bar = makeBar()
        XCTAssertEqual(bar.subviews.count, 4)
        for (index, control) in bar.subviews.enumerated() {
            XCTAssertTrue(control is Control)
            XCTAssertTrue(control.subviews[0] is ImageView, "\(index)")
            XCTAssertFalse(control.subviews.contains(where: { type(of: $0) == View.self && $0.subviews.contains(where: { $0 is ImageView }) }), "\(index)")
        }
        XCTAssertEqual(bar.subviews[2].subviews.count, 2)
    }

    func testIconsSitWhereTheWrapperPutThem() {
        for width in [CGFloat(333), 280, 401] {
            let current = makeBar(width: 300)
            let legacy = makeBar(width: 300)
            wrapLikeBefore(legacy)
            current.setFrameSize(NSMakeSize(width, 50))
            legacy.setFrameSize(NSMakeSize(width, 50))
            for (new, old) in zip(current.subviews, legacy.subviews) {
                let oldIcon = old.subviews[0].subviews[0]
                XCTAssertEqual(new.subviews[0].frame, oldIcon.convert(oldIcon.bounds, to: old), "\(width)")
            }
        }
    }

    func testTabBarRendersLikeTheWrappedTabs() {
        for (width, selected) in [(CGFloat(333), 0), (280, 1), (401, 3)] {
            let current = makeBar(width: width, selected: selected)
            let legacy = makeBar(width: width, selected: selected)
            wrapLikeBefore(legacy)
            let new = ViewSnapshot.render(current)
            XCTAssertEqual(new.differingPixels(from: ViewSnapshot.render(legacy), tolerance: 0), 0, "\(width)")
            let bare = makeBar(width: width, selected: selected)
            bare.subviews[1].subviews[0].isHidden = true
            XCTAssertGreaterThan(new.differingPixels(from: ViewSnapshot.render(bare), tolerance: 0), 1000, "\(width)")
        }
    }

    func testSelectionSwapsTheIconImages() {
        let bar = makeBar(selected: 0)
        bar.setSelectedIndex(2, respondToDelegate: false, animated: false)
        for index in 0 ..< bar.count {
            let icon = bar.subviews[index].subviews[0] as! ImageView
            XCTAssertTrue(icon.image === (index == 2 ? bar.tab(at: index).selectedImage : bar.tab(at: index).image), "\(index)")
        }
    }

    func testReplaceTabUpdatesTheIconInPlaceAndKeepsTheBadge() {
        let bar = makeBar(selected: 2)
        let icon = bar.subviews[2].subviews[0]
        let badge = bar.subviews[2].subviews[1]
        let replacement = makeTab(CGSize(width: 25, height: 19), badge: false)
        bar.replaceTab(TabItem(image: replacement.image, selectedImage: replacement.selectedImage, controller: replacement.controller, subNode: bar.tab(at: 2).subNode), at: 2)
        XCTAssertTrue(bar.subviews[2].subviews[0] === icon)
        XCTAssertTrue((icon as! ImageView).image === replacement.selectedImage)
        XCTAssertTrue(bar.subviews[2].subviews[1] === badge)
        XCTAssertEqual(bar.subviews[2].subviews.count, 2)
    }
}
