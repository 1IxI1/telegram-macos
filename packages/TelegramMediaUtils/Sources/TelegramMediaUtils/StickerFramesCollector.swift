import Foundation
import TelegramMedia

public protocol StickerFramesCollector {
    func collect() -> [Int : LottiePlayerView]
}
