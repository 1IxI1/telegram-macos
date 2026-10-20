import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import MediaRecorderUI
import TelegramMediaUtils

func installMediaRecorderUIHooks() {
    installMediaRecorderHooks(.init(setPendingMedia: { chatInteraction, data in
        guard let chatInteraction = chatInteraction as? ChatInteraction else {
            return
        }
        chatInteraction.mediaPromise.set(data)
    }, clearRecordingState: { chatInteraction in
        guard let chatInteraction = chatInteraction as? ChatInteraction else {
            return
        }
        chatInteraction.update({ $0.withoutRecordingState() })
    }))
}
