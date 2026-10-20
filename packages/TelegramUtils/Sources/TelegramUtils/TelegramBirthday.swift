import Foundation
import TelegramCore
import Localization
import CalendarUtils

public extension TelegramBirthday {
    var isToday: Bool {
        let date = Date()
        let calendar = Calendar.current

        let day = calendar.component(.day, from: date)
        let month = calendar.component(.month, from: date)
        
        return self.day == day && self.month == month
    }
    
    func isTomorrow() -> Bool {
        let currentDate = Date()
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: currentDate) else { return false }

        let dayTomorrow = calendar.component(.day, from: tomorrow)
        let monthTomorrow = calendar.component(.month, from: tomorrow)

        return day == dayTomorrow && month == monthTomorrow
    }

    func isYesterday() -> Bool {
        let currentDate = Date()
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: currentDate) else { return false }

        let dayYesterday = calendar.component(.day, from: yesterday)
        let monthYesterday = calendar.component(.month, from: yesterday)

        return day == dayYesterday && month == monthYesterday
    }
    
    
    func yearsSince() -> Int? {
        
        guard let year else {
            return nil
        }
        
        let calendar = Calendar.current
        
        // Components of the input date
        var dateComponents = DateComponents()
        dateComponents.day = Int(day)
        dateComponents.month = Int(month)
        dateComponents.year = Int(year)
        
        // Construct the date from components
        guard let fromDate = calendar.date(from: dateComponents) else {
            return nil // Invalid date was provided
        }
        
        // Get the current date
        let toDate = Date()
        
        // Calculate the difference in years
        let components = calendar.dateComponents([.year], from: fromDate, to: toDate)
        return components.year
    }

    
    var isEligble: Bool {
        return self.isToday || self.isTomorrow() || self.isYesterday()
    }
    var formatted: String {
        return formatBirthdayToString(day: Int(self.day), month: Int(self.month), year: self.year.flatMap(Int.init)) ?? ""
    }
    var formattedYears: String {
        if let year = yearsSince(), year > 0 {
            let string = formatted + " (\(strings().birthdayYearsOldOther(year)))"
            if isToday {
                return "🎂 " + string
            } else {
                return string
            }
        } else {
            return formatted
        }
    }
}