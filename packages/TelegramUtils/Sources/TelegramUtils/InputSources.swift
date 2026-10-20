import SwiftSignalKit
import TelegramContext
import Foundation
import TelegramCore
import ObjcUtils
import Postbox
import InAppSettings

public final class InputSources: NSObject {
    
    private let _inputSource: Promise<[String]> = Promise(["en"])
    
    public var value: Signal<[String], NoError> {
        _inputSource.set(Signal { subscriber in
            subscriber.putNext([currentKeyboardLanguage()])
            subscriber.putCompletion()
            return EmptyDisposable
        } |> runOn(.mainQueue()))
        return _inputSource.get() |> distinctUntilChanged(isEqual: { $0 == $1 })
    }
    
    public func searchEmoji(postbox: Postbox, engine: TelegramEngine, sharedContext: any SharedAccountContextProtocol, query: String, completeMatch: Bool, checkPrediction: Bool) -> Signal<[String], NoError> {
        return combineLatest(value, baseAppSettings(accountManager: sharedContext.accountManager)) |> mapToSignal { sources, settings in
            if settings.predictEmoji || !checkPrediction {
                func lookup(_ q: String, completeMatch: Bool) -> Signal<[String], NoError> {
                    return combineLatest(sources.map({ engine.stickers.searchEmojiKeywords(inputLanguageCode: $0, query: q.lowercased(), completeMatch: completeMatch) })) |> map { results in
                        let result = results.reduce([], { $0 + $1 })
                        return result.reduce([], { current, value -> [String] in
                            if completeMatch {
                                if q.lowercased() == value.keyword.lowercased() {
                                    return current + value.emoticons
                                } else {
                                    return current
                                }
                            } else {
                                return current + value.emoticons
                            }
                        }).uniqueElements.map { $0.fixed }
                    }
                }
                return lookup(query, completeMatch: completeMatch) |> mapToSignal { phrase -> Signal<[String], NoError> in
                    if !phrase.isEmpty {
                        return .single(phrase)
                    }
                    // The keyword index AND-matches the query's tokens, so a multi-word phrase only hits
                    // genuine multi-word keywords. When that yields nothing, OR the per-word matches so
                    // "rock and" still surfaces every word's emoji instead of going dead.
                    let words = query.lowercased().components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { !$0.isEmpty }
                    guard words.count > 1, !completeMatch else {
                        return .single(query.emojis)
                    }
                    return combineLatest(words.map { lookup($0, completeMatch: false) }) |> map { perWord in
                        let combined = perWord.flatMap { $0 }.uniqueElements
                        return combined.isEmpty ? query.emojis : combined
                    }
                } |> distinctUntilChanged
            } else {
                return .single([])
            }
        }
    }
    
    
    public override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(inputSourceChanged), name: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func inputSourceChanged() {
        _inputSource.set(.single(currentAppInputSource().uniqueElements))
    }
}
