import Foundation
import TelegramCore
import Localization

public func formatDateTimeEntity(format: MessageTextEntityType.DateTimeFormat, date: Int32) -> String {
    let currentTimestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
    switch format {
    case .relative:
        let value = currentTimestamp - date
        if value > 0 {
            if value < 60 {
                return strings().formattedDateSecondsAgoOther(Int(value))
            } else if value <= 1 * 60 * 60 {
                return strings().formattedDateMinutesAgoOther(Int(round(Float(value) / 60)))
            } else if value <= 24 * 60 * 60 {
                return strings().formattedDateHoursAgoOther(Int(round(Float(value) / (60 * 60))))
            } else {
                return strings().formattedDateDaysAgoOther(Int(round(Float(value) / (24 * 60 * 60))))
            }
        } else {
            let value = abs(value)
            if value < 60 {
                return strings().formattedDateInSecondsOther(Int(value))
            } else if value <= 1 * 60 * 60 {
                return strings().formattedDateInMinutesOther(Int(round(Float(value) / 60)))
            } else if value <= 24 * 60 * 60 {
                return strings().formattedDateInHoursOther(Int(round(Float(value) / (60 * 60))))
            } else {
                return strings().formattedDateInDaysOther(Int(round(Float(value) / (24 * 60 * 60))))
            }
        }
    case let .full(timeFormat, dateFormat, dayOfWeek):
        var t: time_t = Int(date)
        var timeinfo = tm()
        localtime_r(&t, &timeinfo)

        var string = ""
        if dayOfWeek {
            string = stringForDayOfWeek(day: Int32(timeinfo.tm_wday), short: dateFormat == .short)
        }
        if let dateFormat {
            if !string.isEmpty {
                string += " "
            }
            switch dateFormat {
            case .short:
                string += stringForEntityShortDate(timeinfo: timeinfo)
            case .long:
                string += stringForEntityLongDate(timeinfo: timeinfo)
            }
        }
        if let timeFormat {
            let timeString: String
            switch timeFormat {
            case .short:
                timeString = stringForShortTimestamp(hours: Int32(timeinfo.tm_hour), minutes: Int32(timeinfo.tm_min))
            case .long:
                timeString = stringForEntityLongTime(date: date)
            }
            if !string.isEmpty {
                string = strings().timeAtPreciseDate(string, timeString)
            } else {
                string = timeString
            }
        }
        return string
    }
}

private func stringForDayOfWeek(day: Int32, short: Bool) -> String {
    switch day {
    case 0: return short ? strings().weekdayShortSunday : strings().weekdaySunday
    case 1: return short ? strings().weekdayShortMonday : strings().weekdayMonday
    case 2: return short ? strings().weekdayShortTuesday : strings().weekdayTuesday
    case 3: return short ? strings().weekdayShortWednesday : strings().weekdayWednesday
    case 4: return short ? strings().weekdayShortThursday : strings().weekdayThursday
    case 5: return short ? strings().weekdayShortFriday : strings().weekdayFriday
    case 6: return short ? strings().weekdayShortSaturday : strings().weekdaySaturday
    default: return ""
    }
}

private func stringForEntityLongTime(date: Int32) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .medium
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(date)))
}

private func stringForEntityShortDate(timeinfo: tm) -> String {
    var separator = "/"
    var suffix = ""
    var requiresFullYear = false
    var monthFirst = false
    if let format = DateFormatter.dateFormat(fromTemplate: "MdY", options: 0, locale: Locale.current) {
        for candidate in [". ", ".", "/", "-"] {
            if format.contains(candidate) {
                if candidate == ". " {
                    suffix = "."
                    separator = "."
                    requiresFullYear = true
                } else {
                    separator = candidate
                }
                break
            }
        }
        monthFirst = format.contains("M\(separator)d")
    }
    let day = timeinfo.tm_mday
    let month = timeinfo.tm_mon + 1
    let year = requiresFullYear ? timeinfo.tm_year - 100 + 2000 : timeinfo.tm_year - 100
    if monthFirst {
        return String(format: "%02d%@%02d%@%02d%@", month, separator, day, separator, year, suffix)
    } else {
        return String(format: "%02d%@%02d%@%02d%@", day, separator, month, separator, year, suffix)
    }
}

private func stringForEntityLongDate(timeinfo: tm) -> String {
    let dayString = "\(timeinfo.tm_mday)"
    let yearString = "\(2000 + timeinfo.tm_year - 100)"
    switch timeinfo.tm_mon + 1 {
    case 1: return strings().formattedDateLongDateM1(dayString, yearString)
    case 2: return strings().formattedDateLongDateM2(dayString, yearString)
    case 3: return strings().formattedDateLongDateM3(dayString, yearString)
    case 4: return strings().formattedDateLongDateM4(dayString, yearString)
    case 5: return strings().formattedDateLongDateM5(dayString, yearString)
    case 6: return strings().formattedDateLongDateM6(dayString, yearString)
    case 7: return strings().formattedDateLongDateM7(dayString, yearString)
    case 8: return strings().formattedDateLongDateM8(dayString, yearString)
    case 9: return strings().formattedDateLongDateM9(dayString, yearString)
    case 10: return strings().formattedDateLongDateM10(dayString, yearString)
    case 11: return strings().formattedDateLongDateM11(dayString, yearString)
    case 12: return strings().formattedDateLongDateM12(dayString, yearString)
    default: return ""
    }
}