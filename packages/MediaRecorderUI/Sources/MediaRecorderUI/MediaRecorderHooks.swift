import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramMediaUtils

public struct MediaRecorderHooks {
    public let setPendingMedia: (Any, Signal<[MediaSenderContainer], NoError>) -> Void
    public let clearRecordingState: (Any) -> Void

    public init(setPendingMedia: @escaping (Any, Signal<[MediaSenderContainer], NoError>) -> Void,
                clearRecordingState: @escaping (Any) -> Void) {
        self.setPendingMedia = setPendingMedia
        self.clearRecordingState = clearRecordingState
    }

    private static var value: MediaRecorderHooks?

    public static var shared: MediaRecorderHooks {
        guard let value = value else {
            preconditionFailure("MediaRecorderHooks not installed")
        }
        return value
    }

    public static func install(_ hooks: MediaRecorderHooks) {
        self.value = hooks
    }
}

public func installMediaRecorderHooks(_ hooks: MediaRecorderHooks) {
    MediaRecorderHooks.install(hooks)
}
