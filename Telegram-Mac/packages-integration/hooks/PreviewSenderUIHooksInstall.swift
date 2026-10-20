import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import PreviewSenderUI

extension EmojiesController: @retroactive PreviewSenderEmojiesController {

}

private func mapPreviewSenderEmojiSelectedItem(_ item: PreviewSenderEmojiSelectedItem) -> EmojiesSectionRowItem.SelectedItem {
    let source: EmojiesSectionRowItem.SelectedItem.Source
    switch item.source {
    case let .builtin(emoji):
        source = .builtin(emoji)
    case let .custom(fileId):
        source = .custom(fileId)
    }
    let type: EmojiesSectionRowItem.SelectedItem.Selection
    switch item.type {
    case .normal:
        type = .normal
    case .transparent:
        type = .transparent
    }
    return EmojiesSectionRowItem.SelectedItem(source: source, type: type)
}

func installPreviewSenderUIHooks() {
    PreviewSenderUIHooks.install(PreviewSenderUIHooks(makeEmojies: { context, presentation in
        return EmojiesController(context as! AccountContext, presentation: presentation)
    }, updateEmojies: { emoji, peerId, sendEmoji, sendAnimatedEmoji, chatInteraction in
        let interactions = EntertainmentInteractions(.emoji, peerId: peerId)

        interactions.sendEmoji = sendEmoji
        interactions.sendAnimatedEmoji = sendAnimatedEmoji

        (emoji as! EmojiesController).update(with: interactions, chatInteraction: chatInteraction)
    }, showMessageEffectsWindow: { context, peerId, selectedItems, react, view in
        let window = ReactionsWindowController(context as! AccountContext, peerId: peerId, selectedItems: selectedItems.map(mapPreviewSenderEmojiSelectedItem), react: react, moveTop: true, mode: .messageEffects)
        window.show(view)
    }))
}
