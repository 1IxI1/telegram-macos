import Foundation
import TelegramCore

public func instantPageRichTextFromBlocks(_ blocks: [InstantPageBlock]) -> RichText {
    var parts: [RichText] = []
    for block in blocks {
        let text: RichText?
        switch block {
        case let .paragraph(t):        text = t
        case let .title(t):            text = t
        case let .subtitle(t):         text = t
        case let .header(t):           text = t
        case let .subheader(t):        text = t
        case let .kicker(t):           text = t
        case let .footer(t):           text = t
        case let .heading(t, _):       text = t
        case let .preformatted(t, _):  text = t
        default:                       text = nil
        }
        if let text = text {
            if !parts.isEmpty { parts.append(.plain("\n")) }
            parts.append(text)
        }
    }
    if parts.isEmpty { return .empty }
    if parts.count == 1 { return parts[0] }
    return .concat(parts)
}
