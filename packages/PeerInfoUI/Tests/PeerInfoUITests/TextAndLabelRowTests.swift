import XCTest
import AppKit
import TGUIKit
import GeneralRows
import TelegramTheme
import TelegramUtils
@testable import PeerInfoUI

final class TextAndLabelRowTests: XCTestCase {
    private struct Config {
        let name: String
        var viewType: GeneralViewType = .singleItem
        var text: String = "Plan like an adult, believe like a child"
        var copy: Bool = false
        var hideText: Bool? = nil
        var gift: Bool = false
        var description: String? = nil
    }

    private static let longText = Array(repeating: "Plan like an adult, believe like a child, and keep every promise.", count: 6).joined(separator: " ")

    private let configs: [Config] = [
        Config(name: "plain", viewType: .firstItem),
        Config(name: "copy", viewType: .innerItem, copy: true),
        Config(name: "more", viewType: .lastItem, text: longText),
        Config(name: "hidden", hideText: true),
        Config(name: "shown", hideText: false),
        Config(name: "gift", gift: true),
        Config(name: "description", copy: true, description: "28 years old"),
        Config(name: "legacy", viewType: .legacy, copy: true),
        Config(name: "everything", viewType: .firstItem, text: longText, copy: true, hideText: false, description: "28 years old"),
    ]

    private let width: CGFloat = 420

    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        LinkHooks.install(LinkHooks(callbackLink: { link, _ in link }, globalLinkExecutor: { TextViewInteractions() }, openExternalLink: { _, _ in }, markdownLink: { $0 }, externalLink: { link, _ in link }, linkPayload: { $0 as? String }, openAnyLink: { _ in }, detectLinks: { _, _ in }))
    }

    private func makeItem(_ config: Config, copied: (() -> Void)? = nil, toggled: (() -> Void)? = nil) -> TextAndLabelItem {
        let item = TextAndLabelItem(NSMakeSize(width, 50), stableId: 0, label: "bio", copyMenuText: "Copy", text: config.text, context: nil, viewType: config.viewType, _copyToClipboard: config.copy ? (copied ?? {}) : nil, hideText: config.hideText, toggleHide: config.hideText != nil ? (toggled ?? {}) : nil, linkInteractions: TextViewInteractions(), gift: config.gift ? {} : nil, description: config.description)
        _ = item.makeSize(width, oldWidth: 0)
        return item
    }

    private func show<T: TableRowView>(_ row: T, _ item: TextAndLabelItem) {
        row.setFrameSize(NSMakeSize(width, item.height))
        row.set(item: item, animated: false)
        row.updateColors()
        row.layout()
    }

    private func container(_ row: NSView) -> NSView {
        return row.subviews.first(where: { $0 is GeneralRowContainerView })!
    }

    private func shownChildren(_ row: NSView) -> [String] {
        return container(row).subviews.filter { !$0.isHidden }.map { String(describing: type(of: $0)) }
    }

    func testRowsRenderLikeTheOldRow() {
        for config in configs {
            let item = makeItem(config)
            let current = TextAndLabelRowView(frame: NSMakeRect(0, 0, width, item.height))
            let legacy = LegacyTextAndLabelRowView(frame: NSMakeRect(0, 0, width, item.height))
            show(current, item)
            show(legacy, item)
            XCTAssertEqual(shownChildren(current), shownChildren(legacy), config.name)
            for (new, old) in zip(container(current).subviews, container(legacy).subviews.filter { !$0.isHidden }) {
                XCTAssertEqual(new.frame, old.frame, config.name)
            }
            XCTAssertEqual(ViewSnapshot.render(current).differingPixels(from: ViewSnapshot.render(legacy), tolerance: 0), 0, config.name)
        }
    }

    func testExtrasAreVisibleInTheRender() {
        let plain = makeItem(Config(name: "plain"))
        let base = TextAndLabelRowView(frame: NSMakeRect(0, 0, width, plain.height))
        show(base, plain)
        let reference = ViewSnapshot.render(base)
        for config in [Config(name: "copy", copy: true), Config(name: "hidden", hideText: false), Config(name: "gift", gift: true)] {
            let item = makeItem(config)
            let row = TextAndLabelRowView(frame: NSMakeRect(0, 0, width, item.height))
            show(row, item)
            XCTAssertGreaterThan(ViewSnapshot.render(row).differingPixels(from: reference, tolerance: 0), 100, config.name)
        }
        let more = makeItem(Config(name: "more", text: TextAndLabelRowTests.longText))
        XCTAssertEqual(more.hasMore, true)
    }

    func testPlainRowHoldsOnlyItsText() {
        let row = TextAndLabelRowView(frame: NSMakeRect(0, 0, width, 50))
        show(row, makeItem(Config(name: "plain")))
        XCTAssertEqual(container(row).subviews.count, 1)
        XCTAssertTrue(container(row).subviews.first is InteractiveTextView)
    }

    func testReusedRowMatchesAFreshOldRow() {
        let everything = configs.last!
        let row = TextAndLabelRowView(frame: NSMakeRect(0, 0, width, 50))
        show(row, makeItem(everything))
        show(row, makeItem(Config(name: "plain")))
        XCTAssertEqual(container(row).subviews.count, 1)
        show(row, makeItem(Config(name: "description", copy: true, description: "28 years old")))
        let item = makeItem(everything)
        show(row, item)
        let legacy = LegacyTextAndLabelRowView(frame: NSMakeRect(0, 0, width, item.height))
        show(legacy, item)
        XCTAssertEqual(shownChildren(row), shownChildren(legacy))
        XCTAssertEqual(ViewSnapshot.render(row).differingPixels(from: ViewSnapshot.render(legacy), tolerance: 0), 0)
    }

    func testButtonsReachTheirActions() {
        var copied = 0
        var toggled = 0
        let row = TextAndLabelRowView(frame: NSMakeRect(0, 0, width, 50))
        show(row, makeItem(Config(name: "both", copy: true, hideText: true), copied: { copied += 1 }, toggled: { toggled += 1 }))
        let buttons = container(row).subviews.compactMap { $0 as? ImageButton }
        XCTAssertEqual(buttons.count, 2)
        buttons.forEach { $0.send(event: .Click) }
        XCTAssertEqual(copied, 1)
        XCTAssertEqual(toggled, 1)
        XCTAssertTrue(buttons.allSatisfy { $0.scaleOnClick && !$0.autohighlight })
    }
}
