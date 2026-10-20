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
import GZIP

private let videoCameraRetainedBufferCount:Int = 16;

private let roundVideoPlaneFrameCount = 27

private func roundVideoDecoration() -> (watermark: CGImage, planeFrames: CGImage)? {
    guard let watermark = NSImage(named: "RoundVideoCorner")?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }
    guard let data = NSDataAsset(name: "PlaneLogoPlain")?.data, let unzipped = TGGUnzipData(data, 5 * 1024 * 1024), let json = String(data: unzipped, encoding: .utf8), let animation = LottieRenderHooks.shared.makeRenderer(json, "PlaneLogoPlain") else {
        return nil
    }
    let frameSize = 68
    let bytesPerRow = frameSize * 4
    let frameByteCount = bytesPerRow * frameSize
    var bytes = Data(count: frameByteCount * roundVideoPlaneFrameCount)
    bytes.withUnsafeMutableBytes { buffer in
        guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
            return
        }
        for index in 0 ..< roundVideoPlaneFrameCount {
            animation.renderFrame(with: Int32(index * 2), into: base.advanced(by: index * frameByteCount), width: Int32(frameSize), height: Int32(frameSize), bytesPerRow: Int32(bytesPerRow))
        }
    }
    let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
    guard let provider = CGDataProvider(data: bytes as CFData), let planeFrames = CGImage(width: frameSize, height: frameSize * roundVideoPlaneFrameCount, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo, provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
        return nil
    }
    return (watermark, planeFrames)
}

private func passthroughExport(asset: AVAsset, name: String, timeRange: CMTimeRange? = nil) -> Signal<String?, NoError> {
    return Signal { subscriber in
        let path = temporaryMediaPath(name, "mp4")
        let output = URL(fileURLWithPath: path)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            removeFile(at: path)
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        export.outputURL = output
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        if let timeRange {
            export.timeRange = timeRange
        }
        export.exportAsynchronously {
            if export.status == .completed {
                subscriber.putNext(path)
            } else {
                removeFile(at: path)
                subscriber.putNext(nil)
            }
            subscriber.putCompletion()
        }
        return ActionDisposable {
            export.cancelExport()
        }
    }
}

public func exportTrimmedVideo(path: String, range: Range<Double>) -> Signal<String?, NoError> {
    let timeRange = CMTimeRange(start: CMTimeMakeWithSeconds(range.lowerBound, preferredTimescale: 1000), end: CMTimeMakeWithSeconds(range.upperBound, preferredTimescale: 1000))
    return passthroughExport(asset: AVURLAsset(url: URL(fileURLWithPath: path)), name: "video_message_trim", timeRange: timeRange)
}




public class VideoRecorderPipeline : NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, TGVideoCameraMovieRecorderDelegate, AVCaptureAudioDataOutputSampleBufferDelegate  {
    
    
    public func movieRecorderDidFinishPreparing(_ recorder: TGVideoCameraMovieRecorder!) {
        
    }
    
    public func movieRecorder(_ recorder: TGVideoCameraMovieRecorder!, didFailWithError error: Error!) {
        status = .failed
    }
    
    public func movieRecorderDidFinishRecording(_ recorder: TGVideoCameraMovieRecorder!) {
        VideoRecorderPipeline.queue.async {
            self.segments.append(self.currentURL)
            self.completedDuration += self.lastSegmentDuration
            self.lastSegmentDuration = 0
            
            switch self.status {
            case .startingRecording, .recording, .madeThumbnail:
                self.composedRecording { path, duration in
                    self.status = .paused(info: ChatRecordingPreviewData(path: path, duration: duration, waveform: nil, thumb: self.thumbnail))
                }
            default:
                self.finishWithComposedResult()
            }
        }
    }
    
    
    
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private var videoConnection:AVCaptureConnection?
    private var videoDevice: AVCaptureDevice?
    
    private var audioDeviceInput: AVCaptureDeviceInput?
    private let audioOutput = AVCaptureAudioDataOutput()
    private var audioConnection:AVCaptureConnection?
    private var audioDevice: AVCaptureDevice?

    
    private var outputVideoFormatDescription: CMFormatDescription?
    private var outputAudioFormatDescription: CMFormatDescription?
    
    public private(set) var thumbnail:CGImage?
    
    public let session: AVCaptureSession = AVCaptureSession()
    
    public let config: VideoMessageConfig
    
    private var status: VideoCameraRecordingStatus = .idle {
        didSet {
            statePromise.set(status)
        }
    }
    
    public let statePromise:ValuePromise<VideoCameraRecordingStatus> = ValuePromise(.idle, ignoreRepeated: true)
    public let powerAndDuration: Promise<(Float, Double)> = Promise()
    
    public var pausedInfo: Signal<ChatRecordingPreviewData?, NoError> {
        return statePromise.get() |> map { state in
            if case let .paused(info) = state {
                return info
            }
            return nil
        } |> distinctUntilChanged
    }
    
    private let renderer:TGVideoCameraGLRenderer = TGVideoCameraGLRenderer()
    private var renderingEnabled: Bool = false

    private var recorder: TGVideoCameraMovieRecorder!
    
    
    private let path: String
    private let url:URL
    private var currentURL: URL
    private var segments: [URL] = []
    private var derivedFiles: [String] = []
    private var composedFile: String?
    private var sentPath: String?
    private var isDiscarded: Bool = false
    private var completedDuration: Double = 0
    private var lastSegmentDuration: Double = 0
    private var isPaused: Bool = false
    private let composeDisposable = MetaDisposable()
    
    private var currentSegmentDuration: Double {
        let duration = recorder.videoDuration()
        return duration.isNaN ? 0 : duration
    }
    
    private var resultDuration: Int = 0
    private var startTimeInterval: TimeInterval = 0
    private var decorationStartTime: CMTime?

    private static let queue: Queue = Queue(name: "org.telegram.InstantVideoQueue")
    
    private let startRecordAfterAudioBuffer:Atomic<Bool> = Atomic(value: false)
    private var pipelineSetupFailed: Bool = false

    public static let videoMessageMaxDuration: Double = 60

    private var liveUploading: PreUploadManager?
    public init(path: String, config: VideoMessageConfig, liveUploading: PreUploadManager?) {
        self.path = path
        let url = URL(fileURLWithPath: path)
        self.url = url
        self.currentURL = url
        self.liveUploading = liveUploading
        self.config = config
        super.init()
        
        recorder = TGVideoCameraMovieRecorder(url: url, delegate: self, callbackQueue: VideoRecorderPipeline.queue.queue)
        
        renderer.orientation = .portrait
        renderer.mirror = true
        if let decoration = roundVideoDecoration() {
            renderer.setDecorationWatermark(decoration.watermark, planeFrames: decoration.planeFrames, planeFrameCount: roundVideoPlaneFrameCount)
        }
        
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else {
            session.sessionPreset = .medium
        }
        

        let defAudioDevice = AVCaptureDevice.default(for: .audio)
        let defVideoDevice = AVCaptureDevice.default(for: .video)
        
        
        var videoDevices = AVCaptureDevice.devices(for: .video).filter({ $0.isConnected && !$0.isSuspended })
        var audioDevices = AVCaptureDevice.devices(for: .audio)

        if !videoDevices.isEmpty, let device = defVideoDevice {
            videoDevices.insert(device, at: 0)
        }
        if !audioDevices.isEmpty, let device = defAudioDevice {
            audioDevices.insert(device, at: 0)
        }
            
        let videoDevice = videoDevices.filter({ $0.isConnected && !$0.isSuspended }).first(where: { $0.position == .front || $0.position == .unspecified })
        
        let audioDevice = audioDevices.first(where: { $0.isConnected && !$0.isSuspended})


        if let videoDevice = videoDevice {
            setSelectedVideoDevice(videoDevice)
        } else if let videoDevice = AVCaptureDevice.default(for: .muxed) {
            setSelectedVideoDevice(videoDevice)
        }
        
        if let audioDevice = audioDevice {
            setSelectedAudioDevice(audioDevice)
        }
        
        videoOutput.alwaysDiscardsLateVideoFrames = false

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferIOSurfacePropertiesKey as String: [:], kCVPixelBufferWidthKey as String: 500, kCVPixelBufferHeightKey as String: 500]
        
        videoOutput.setSampleBufferDelegate(self, queue: VideoRecorderPipeline.queue.queue)
        session.addOutput(videoOutput)

        audioOutput.setSampleBufferDelegate(self, queue: VideoRecorderPipeline.queue.queue)
        
        
        session.addOutput(audioOutput)
        
        
        videoConnection = videoOutput.connection(with: .video)
        audioConnection = audioOutput.connection(with: .audio)

        
        _configureFps()
    }
    
    private func _configureFps() {
        
        //let frameDuration = CMTimeMake(1, 30)
        
        if let videoDevice = videoDevice {
            _reconfigureDevice(videoDevice, with: { device in
               // device.activeVideoMaxFrameDuration = frameDuration
               // device.activeVideoMinFrameDuration = frameDuration
            })
        }
    }
    
    private func _reconfigureDevice(_ device: AVCaptureDevice, with block: (AVCaptureDevice)-> Void) {
        try? device.lockForConfiguration()
        block(device)
        device.unlockForConfiguration()
    }
    

    private func setSelectedAudioDevice(_ device: AVCaptureDevice) {
        self.audioDevice = device
        session.beginConfiguration()
        if let audioDeviceInput = audioDeviceInput {
            session.removeInput(audioDeviceInput)
            self.audioDeviceInput = nil
        }
        if let audioDeviceInput = try? AVCaptureDeviceInput(device: device)  {
            if !device.supportsSessionPreset(session.sessionPreset) {
                session.sessionPreset = .high
            }
            session.addInput(audioDeviceInput)
            self.audioDeviceInput = audioDeviceInput
        }
        session.commitConfiguration()
    }
    
    private func setSelectedVideoDevice(_ device: AVCaptureDevice) {
        self.videoDevice = device
        
        session.beginConfiguration()
        if let videoDeviceInput = videoDeviceInput {
            session.removeInput(videoDeviceInput)
            self.videoDeviceInput = nil
        }
        if let videoDeviceInput = try? AVCaptureDeviceInput(device: device)  {
            if !device.supportsSessionPreset(session.sessionPreset) {
                session.sessionPreset = .high
            }
            session.addInput(videoDeviceInput)
            self.videoDeviceInput = videoDeviceInput
        }
        session.commitConfiguration()
    }
  
    
    
    
    private func setupVideoPipelineWithInputFormatDescription(_ inputFormatDescription: CMFormatDescription) {
        let prepared = renderer.prepareForInput(with: inputFormatDescription, outputRetainedBufferCountHint: videoCameraRetainedBufferCount)
        self.outputVideoFormatDescription = renderer.outputFormatDescription
        
        if !prepared || self.outputVideoFormatDescription == nil {
            self.pipelineSetupFailed = true
            self.status = .failed
            return
        }
        
        self.startRecording()
    }
    

   
    private let skip:Atomic<Int32> = Atomic(value: 0)
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        
        
        let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
        
        if self.skip.modify({ $0 + 1 }) < 10 {
            return
        }
        
        if connection == self.videoConnection, let formatDescription = formatDescription {
            
            if self.outputVideoFormatDescription != nil {
                self.renderVideoSampleBuffer(sampleBuffer)
            } else if !pipelineSetupFailed {
                self.setupVideoPipelineWithInputFormatDescription(formatDescription)
            }
            
            
        } else if connection == self.audioConnection {
            self.outputAudioFormatDescription = formatDescription
            
            if startRecordAfterAudioBuffer.swap(false) {
                self.startRecording()
                return
            }
            
            if isPaused {
                return
            }
            
            recorder.appendAudioSampleBuffer(sampleBuffer)
            
            if renderingEnabled {
                lastSegmentDuration = currentSegmentDuration
                let duration = completedDuration + lastSegmentDuration
                let power = connection.audioChannels.map { Float(mappingRange(Double($0.averagePowerLevel), -60, 0, 0, 1)) }.max() ?? 0
                powerAndDuration.set(.single((power, duration)))
            }
        }
        liveUploading?.fileDidChangedSize(false)
    }
    

    
    private func renderVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        var renderedPixelBuffer: CVPixelBuffer? = nil
        let timestamp: CMTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        if renderingEnabled, !isPaused, let sourcePixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let decorationStartTime = self.decorationStartTime ?? timestamp
            self.decorationStartTime = decorationStartTime
            let decorationTime = CMTimeGetSeconds(CMTimeSubtract(timestamp, decorationStartTime))
            renderer.decorationFrame = decorationTime.isFinite ? Int(max(0, decorationTime) * 30) : 0

            renderedPixelBuffer = renderer.copyRenderedPixelBuffer(sourcePixelBuffer).takeRetainedValue()
            
        }
        if let renderedPixelBuffer = renderedPixelBuffer {
            if thumbnail == nil {
                if let thumb = renderedPixelBuffer.cgImage {
                    status = .madeThumbnail(thumb)
                    thumbnail = thumb
                }
            }
            recorder?.appendVideoPixelBuffer(renderedPixelBuffer, withPresentationTime: timestamp)
        }
        
    }
    



    private func startRecording() {
        
        if renderingEnabled {
            return
        }

        if outputAudioFormatDescription == nil {
            _ = startRecordAfterAudioBuffer.swap(true)
            return
        }

        renderingEnabled = true
        status = .recording
        startTimeInterval = Date().timeIntervalSince1970

        configureRecorderTracks()
    }
    
    private func configureRecorderTracks() {
        let audioSettings = TGMediaVideoConversionPresetSettings.audioSettings(for: TGMediaVideoConversionPresetVideoMessage, bitrate: Int32(config.audioBitrate))
        recorder.addAudioTrack(withSourceFormatDescription: outputAudioFormatDescription, settings: audioSettings)
        let size: CGSize = TGMediaVideoConversionPresetSettings.maximumSize(for: TGMediaVideoConversionPresetVideoMessage)
        let videoSettings = TGMediaVideoConversionPresetSettings.videoSettings(for: TGMediaVideoConversionPresetVideoMessage, dimensions: size, bitrate: Int32(config.videoBitrate))
        recorder.addVideoTrack(withSourceFormatDescription: outputVideoFormatDescription, transform: CGAffineTransform.identity, settings: videoSettings)
        
        recorder.prepareToRecord()
    }
    
    public func pause() {
        VideoRecorderPipeline.queue.async {
            guard !self.isPaused, self.renderingEnabled else {
                return
            }
            self.lastSegmentDuration = self.currentSegmentDuration
            self.isPaused = true
            self.renderingEnabled = false
            self.recorder.finishRecording()
        }
    }
    
    public func resume() {
        VideoRecorderPipeline.queue.async {
            guard self.isPaused else {
                return
            }
            self.clearComposedURL()
            self.liveUploading = nil
            
            let next = temporaryMediaPath("video_message_part", "mp4")
            self.derivedFiles.append(next)
            let nextURL = URL(fileURLWithPath: next)
            self.currentURL = nextURL
            self.recorder = TGVideoCameraMovieRecorder(url: nextURL, delegate: self, callbackQueue: VideoRecorderPipeline.queue.queue)
            self.configureRecorderTracks()
            
            self.isPaused = false
            self.renderingEnabled = true
            self.status = .recording
        }
    }
    
    private func finishWithComposedResult() {
        self.composedRecording { path, duration in
            self.resultDuration = Int(ceil(duration))
            let isOriginalFile = self.segments == [self.url]
            if isOriginalFile {
                self.liveUploading?.fileDidChangedSize(true)
            }
            if !self.isDiscarded {
                self.sentPath = path
            }
            self.status = .finishRecording(path: path, duration: self.resultDuration, id: isOriginalFile ? self.liveUploading?.id : nil, thumb: self.thumbnail)
        }
    }

    private func removeUnlessSent(_ path: String) {
        guard path != self.sentPath else {
            return
        }
        removeFile(at: path)
    }

    private func clearComposedURL() {
        if let composedFile = self.composedFile {
            removeUnlessSent(composedFile)
            self.composedFile = nil
        }
    }

    private func removeSegmentFiles() {
        clearComposedURL()
        for derived in derivedFiles {
            removeUnlessSent(derived)
        }
        derivedFiles = []
    }

    private func removeAllFiles() {
        removeSegmentFiles()
        removeUnlessSent(self.path)
    }
    
    public func applyTrim(_ range: Range<Double>) -> Signal<Bool, NoError> {
        return Signal { subscriber in
            let exportDisposable = MetaDisposable()
            VideoRecorderPipeline.queue.async {
                guard self.isPaused else {
                    subscriber.putNext(false)
                    subscriber.putCompletion()
                    return
                }
                self.composedRecording { path, _ in
                    exportDisposable.set(exportTrimmedVideo(path: path, range: range).start(next: { output in
                        VideoRecorderPipeline.queue.async {
                            if let output {
                                self.removeSegmentFiles()
                                self.derivedFiles.append(output)
                                self.segments = [URL(fileURLWithPath: output)]
                                self.completedDuration = range.upperBound - range.lowerBound
                                self.lastSegmentDuration = 0
                                self.liveUploading = nil
                                subscriber.putNext(true)
                            } else {
                                subscriber.putNext(false)
                            }
                            subscriber.putCompletion()
                        }
                    }))
                }
            }
            return exportDisposable
        }
    }
    
    private func composedRecording(_ completion: @escaping (String, Double) -> Void) {
        if self.segments.count == 1, let single = self.segments.first {
            completion(single.path, self.completedDuration)
            return
        }
        self.clearComposedURL()
        
        let composition = AVMutableComposition()
        for segment in self.segments {
            let asset = AVURLAsset(url: segment)
            guard let video = asset.tracks(withMediaType: .video).first else {
                continue
            }
            try? composition.insertTimeRange(video.timeRange, of: asset, at: composition.duration)
        }
        
        let duration = CMTimeGetSeconds(composition.duration)
        composeDisposable.set(passthroughExport(asset: composition, name: "video_message_joined").start(next: { [weak self] output in
            VideoRecorderPipeline.queue.async {
                guard let self else {
                    if let output {
                        removeFile(at: output)
                    }
                    return
                }
                if let output {
                    self.composedFile = output
                    completion(output, duration.isNaN ? self.completedDuration : duration)
                } else {
                    completion(self.segments.last?.path ?? self.url.path, self.completedDuration)
                }
            }
        }))
    }

    
    deinit {
        VideoRecorderPipeline.queue.sync {
            stopCapture()
            removeAllFiles()
        }
        composeDisposable.dispose()
    }

    
    public func stop() {
        VideoRecorderPipeline.queue.async {
            if case .finishRecording = self.status {
                return
            }
            self.status = .stoppingRecording
            self.videoOutput.setSampleBufferDelegate(nil, queue: nil)
            self.audioOutput.setSampleBufferDelegate(nil, queue: nil)
            if self.isPaused {
                if self.completedDuration >= 0.5 {
                    self.finishWithComposedResult()
                } else {
                    self.dispose()
                }
                return
            }
            
            self.lastSegmentDuration = self.currentSegmentDuration
            if self.completedDuration + self.lastSegmentDuration >= 0.5 {
                self.recorder.finishRecording()
            } else {
                self.dispose()
            }
        }
    }
    
    public func stopCapture() {
        VideoRecorderPipeline.queue.async {
            self.session.stopRunning()
        }
    }
    
    public func dispose() {
        VideoRecorderPipeline.queue.async {
            self.isDiscarded = true
            self.sentPath = nil
            if case .finishRecording = self.status {
                return
            }
            self.status = .stopped(thumb: self.thumbnail)
            self.lastSegmentDuration = self.currentSegmentDuration
            self.resultDuration = Int(ceil(self.completedDuration + self.lastSegmentDuration))
        }
    }
  
    
    public func start() {
        VideoRecorderPipeline.queue.async {
            self.status = .startingRecording
            self.session.startRunning()
        }
    }
}
