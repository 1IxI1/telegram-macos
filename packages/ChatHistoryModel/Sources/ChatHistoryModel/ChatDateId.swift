import Foundation

/// `Calendar.current` reads user locale + timezone on every access (involves
/// internal locking and CFLocale reads, ~few hundred ns to ~µs). Both
/// `chatDateId` / `mediaDateId` were paying that cost per message — a chat
/// with 200 messages walked it 200 times. Cache once at module load; the
/// calendar is immutable enough for our purposes (date-group bucketing).
/// If the user changes locale mid-session we'd be one launch behind, which
/// is the same trade-off `Calendar.current`-callers across the codebase make.
private let _chatGroupingCalendar = Calendar.current

/// Day-boundary cache. Chat messages cluster within a small window of days
/// (one chat-open shows messages from ~1-5 days typically), so a tiny LRU
/// of recent day spans hits ~99% of the time and skips the
/// `startOfDay`/calendar timezone computation entirely.
private struct ChatDayBoundary {
    let startUnix: Int64
    let endUnix: Int64
    let dayId: Int64
}
private var _chatDateCache: [ChatDayBoundary] = []
private let _chatDateCacheLock = NSLock()
private let _chatDateCacheCapacity = 16

public func chatDateId(for timestamp: Int32) -> Int64 {
    let ts = Int64(timestamp)
    _chatDateCacheLock.lock()
    for boundary in _chatDateCache {
        if ts >= boundary.startUnix && ts < boundary.endUnix {
            _chatDateCacheLock.unlock()
            return boundary.dayId
        }
    }
    _chatDateCacheLock.unlock()

    let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
    let startOfDay = _chatGroupingCalendar.startOfDay(for: date)
    // Compute the actual end of day (next-day midnight) instead of
    // assuming +86400 — DST transitions can produce 23h or 25h days.
    let endOfDay = _chatGroupingCalendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86400)
    let startUnix = Int64(startOfDay.timeIntervalSince1970)
    let endUnix = Int64(endOfDay.timeIntervalSince1970)
    let dayId = startUnix

    _chatDateCacheLock.lock()
    if _chatDateCache.count >= _chatDateCacheCapacity {
        _chatDateCache.removeFirst()
    }
    _chatDateCache.append(ChatDayBoundary(startUnix: startUnix, endUnix: endUnix, dayId: dayId))
    _chatDateCacheLock.unlock()
    return dayId
}

public func mediaDateId(for timestamp: Int32) -> Int64 {
    let startMonth = _chatGroupingCalendar.date(from: _chatGroupingCalendar.dateComponents([.year, .month], from: Date(timeIntervalSince1970: TimeInterval(timestamp))))!
    let endMonth = _chatGroupingCalendar.date(byAdding: DateComponents(month: 1, day: -1), to: startMonth)!
    return Int64(endMonth.timeIntervalSince1970)
}
