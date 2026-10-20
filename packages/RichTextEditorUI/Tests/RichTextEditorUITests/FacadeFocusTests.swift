#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

/// The canvas (the NSTextInputClient that handles keyDown) must end up as the window's first responder
/// when the host focuses the editor — otherwise typing-on-launch is dead (the façade has no keyDown).
@available(macOS 12, *)
final class FacadeFocusTests: AppKitTestCase {
    func test_focusingFacade_makesCanvasFirstResponder() {
        let editor = RichTextEditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        editor.document = Document(blocks: [.paragraph(ParagraphBlock(id: BlockID.generate()))])
        let win = hostInWindow(editor)
        editor.makeEditorFirstResponder()
        XCTAssertTrue(win.firstResponder === editor.canvas,
                      "the canvas must be first responder so keyDown reaches the editor")
    }

    func test_canvasDoesNotInheritATableAccessibilityParent() {
        let editor = RichTextEditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))

        XCTAssertNil(editor.canvas.accessibilityParent(),
                     "the focused canvas must not ask AppKit to synthesize a table-cell accessibility parent")
    }

    func test_nonScrollingModeHostsCanvasDirectly() {
        let editor = RichTextEditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))

        editor.isScrollEnabled = false
        editor.layoutSubtreeIfNeeded()

        XCTAssertTrue(editor.canvas.superview === editor,
                      "a non-scrolling editor must not retain an NSScrollView between its canvas and host")
        XCTAssertFalse(editor.subviews.contains { $0 is NSScrollView },
                       "the internal scroll view must be detached from a table-backed editor")
        XCTAssertTrue(editor.inputResponder === editor.canvas,
                      "hosts must receive the actual text-input responder rather than the façade")
    }

    func test_reenablingScrollingReparentsTheExistingCanvas() {
        let editor = RichTextEditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let canvas = editor.canvas
        editor.isScrollEnabled = false

        editor.isScrollEnabled = true
        editor.layoutSubtreeIfNeeded()

        XCTAssertTrue(editor.canvas === canvas)
        XCTAssertTrue(editor.canvas.superview is NSClipView,
                      "re-enabling scrolling must restore the canvas as the scroll view document")
        XCTAssertTrue(editor.subviews.contains { $0 is NSScrollView })
    }
}
#endif
