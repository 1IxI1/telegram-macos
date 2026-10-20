import Cocoa
import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import ObjcUtils
import TGVideoCameraMovie
import AVFoundation

public struct VideoRecorderPreviewCommand {
    public let trimRange: Range<Double>?
    public let seekTo: Double
    public let play: Bool
    public init(trimRange: Range<Double>?, seekTo: Double, play: Bool) {
        self.trimRange = trimRange
        self.seekTo = seekTo
        self.play = play
    }
}

public enum VideoCameraRecordingStatus : Equatable {
    case idle
    case startingRecording
    case recording
    case madeThumbnail(CGImage)
    case stoppingRecording
    case paused(info: ChatRecordingPreviewData)
    case stopped(thumb: CGImage?)
    case failed
    case finishRecording(path:String, duration:Int, id: Int64?, thumb: CGImage?)
}

public func ==(lhs: VideoCameraRecordingStatus, rhs: VideoCameraRecordingStatus) -> Bool {
    switch lhs {
    case .idle:              if case .idle = rhs { return true }
    case .startingRecording: if case .startingRecording = rhs { return true }
    case .recording:         if case .recording = rhs { return true }
    case .madeThumbnail:     if case .madeThumbnail = rhs { return true }
    case .stoppingRecording: if case .stoppingRecording = rhs { return true }
    case .paused:            if case .paused = rhs { return true }
    case .stopped:           if case .stopped = rhs { return true }
    case .failed:            if case .failed = rhs { return true }
    case .finishRecording:   if case .finishRecording = rhs { return true }
    }
    return false
}
