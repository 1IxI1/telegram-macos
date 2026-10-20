import Cocoa
import RLottie

extension RLottieBridge: @retroactive LottieFrameRenderer {}

func installLottieRenderHooks() {
    LottieRenderHooks.install(LottieRenderHooks(makeRenderer: { json, key in
        return RLottieBridge(json: json, key: key)
    }))
}
