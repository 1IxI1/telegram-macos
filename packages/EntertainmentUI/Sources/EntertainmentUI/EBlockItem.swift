import Cocoa
import TGUIKit
import TelegramCore
import SwiftSignalKit
import InAppSettings
import Strings

public class EBlockItem: TableRowItem {

    private let _stableId:AnyHashable
    public override var stableId: AnyHashable {
        return _stableId
    }
    
    public override var height: CGFloat {
        return (CGFloat(lineAttr.count) * 34.0)
    }
    
    public let lineAttr:[[NSAttributedString]]
    
    public let account: Account
    public var selectHandler:(String, NSRect)->Void = { _, _ in}
    public let segment: EmojiSegment
    
    public init(_ initialSize:NSSize, stableId: AnyHashable, attrLines:[[NSAttributedString]], segment: EmojiSegment, account: Account, selectHandler:@escaping(String, NSRect)->Void) {
        self.lineAttr = attrLines
        self._stableId = stableId
        self.account = account
        self.segment = segment
        self.selectHandler = selectHandler
        
        super.init(initialSize)
    }
    
    override open func viewClass() ->AnyClass {
        return EBlockRowView.self;
    }
    
    
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        var items: [ContextMenuItem] = []
        let postbox = self.account.postbox
        if let view = self.view as? EBlockRowView {
            if let emoji = view.emojiUnderMouse?.emojiUnmodified, emoji.canHaveSkinToneModifier {
                items.append(EmojiToleranceContextMenuItem(emoji: emoji, callback: { value in
                    _ = modifySkinEmoji(emoji, modifier: value, postbox: postbox).start()
                }))
            }
        }
        
       
        return .single(items)
    }
}
