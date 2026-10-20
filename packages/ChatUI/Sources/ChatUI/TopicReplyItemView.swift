import Cocoa
import Foundation
import TGUIKit
import TelegramCore
import SwiftSignalKit
import Postbox
import ColorPalette
import TGModernGrowingTextView
import Strings
import TelegramContext
import TelegramTheme
import TelegramUtils
import InlineStickerLayer

public final class TopicReplyItemLayout {
    public let context: any AccountContextProtocol
    public let message: Message
    public let text: TextViewLayout
    public let threadData: Message.AssociatedThreadInfo
    public let maxiumLines: Int32
    private let bgColor: NSColor
    private let textColor: NSColor
    public let isSideAccessory: Bool
    public init(context: any AccountContextProtocol, message: Message, isIncoming: Bool, isBubbled: Bool, threadData: Message.AssociatedThreadInfo, maxiumLines: Int32, isSideAccessory: Bool) {
        self.context = context
        self.message = message
        self.threadData = threadData
        self.maxiumLines = maxiumLines
        if isSideAccessory {
            self.bgColor = theme.colors.background
            self.textColor = theme.colors.text
        } else {
            if isIncoming || !isBubbled {
                self.bgColor = theme.colors.accent.withAlphaComponent(0.2)
                self.textColor = theme.colors.accent
            } else {
                self.bgColor = theme.chat.grayText(false, true).withAlphaComponent(0.1)
                self.textColor = theme.chat.grayText(false, true)
            }
        }
        self.isSideAccessory = isSideAccessory
        let attr = NSMutableAttributedString()
        
        _ = attr.append(string: "\(clown) " + threadData.title, color: self.textColor, font: .normal(.text))
        
        let range = attr.string.nsstring.range(of: clown)
        if range.location != NSNotFound {
            let item: InlineStickerItem
            if let fileId = threadData.icon {
                item = .init(source: .attribute(.init(fileId: fileId, file: message.associatedMedia[MediaId(namespace: Namespaces.Media.CloudFile, id: fileId)] as? TelegramMediaFile, emoji: "")))
            } else {
                let file = ChatInterfaceHooks.shared.makeTopicIconFile(threadData.title, threadData.iconColor, message.threadId == 1)
                item = .init(source: .attribute(.init(fileId: Int64(threadData.iconColor), file: file, emoji: "")))
            }
            attr.addAttribute(TextInputAttributes.embedded, value: item, range: range)
        }
        
        self.text = .init(attr, maximumNumberOfLines: maxiumLines, alignment: .left, alwaysStaticItems: true)
    }
    
    public private(set) var size: NSSize = .zero
    
    public func measure(_ width: CGFloat) {
        
        text.measure(width: width)
        self.text.generateAutoBlock(backgroundColor: bgColor, minusHeight: 0, yInset: 1)
        self.size = NSMakeSize(text.layoutSize.width, text.layoutSize.height - 8)
        
    }
}

public final class TopicReplyItemView : Control {
    private let textView = TextView()
    private var inlineStickerItemViews: [InlineStickerItemLayer.Key: InlineStickerItemLayer] = [:]

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        scaleOnClick = true
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(item: TopicReplyItemLayout, animated: Bool) {
        textView.update(item.text)
        updateInlineStickers(context: item.context, view: textView, textLayout: item.text)
    }
    
    public func updateInlineStickers(context: any AccountContextProtocol, view textView: TextView, textLayout: TextViewLayout) {
        var validIds: [InlineStickerItemLayer.Key] = []
        var index: Int = textView.hashValue

        for item in textLayout.embeddedItems {
            if let stickerItem = item.value as? InlineStickerItem, case let .attribute(emoji) = stickerItem.source {
                
                let id = InlineStickerItemLayer.Key(id: emoji.fileId, index: index)
                validIds.append(id)
                
                
                var rect: NSRect
                rect = item.rect.insetBy(dx: 2, dy: 2)

                rect = rect.offsetBy(dx: 6, dy: 2)

                
                let view: InlineStickerItemLayer
                if let current = self.inlineStickerItemViews[id], current.frame.size == rect.size {
                    view = current
                } else {
                    self.inlineStickerItemViews[id]?.removeFromSuperlayer()
                    view = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: emoji, size: rect.size, playPolicy: .playCount(2))
                    self.inlineStickerItemViews[id] = view
                    view.superview = textView
                    textView.addEmbeddedLayer(view)
                }
                index += 1
                view.frame = rect
            }
        }
        
        var removeKeys: [InlineStickerItemLayer.Key] = []
        for (key, itemLayer) in self.inlineStickerItemViews {
            if !validIds.contains(key) {
                removeKeys.append(key)
                itemLayer.removeFromSuperlayer()
            }
        }
        for key in removeKeys {
            self.inlineStickerItemViews.removeValue(forKey: key)
        }
        updateAnimatableContent()
    }
    
    public func updateAnimatableContent() -> Void {
        for (_, value) in inlineStickerItemViews {
            if let superview = value.superview {
                var isKeyWindow: Bool = false
                if let window = self.window {
                    if !window.canBecomeKey {
                        isKeyWindow = true
                    } else {
                        isKeyWindow = window.isKeyWindow
                    }
                }
                value.isPlayable = NSIntersectsRect(value.frame, superview.visibleRect) && isKeyWindow
            }
        }
    }

    
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: textView, frame: textView.centerFrameX(y: 0))
    }
}
