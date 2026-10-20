import Foundation
import AppKit
import Strings

public extension Date {
    var startOfDay: Date {
        let calendar = NSCalendar.current
        return calendar.startOfDay(for: self)
    }
    
    var endOfDay: Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        let calendar = NSCalendar.current
        return calendar.date(byAdding: components, to: startOfDay)!
    }
    
}

public extension String {
    func spoiler(_ range: NSRange) -> String {
        let string = self.nsstring
        
        var rep: String = ""
        
        let chars = Array("⠁⠂⠄⠈⠐⠠⡀⢀⠃⠅⠆⠉⠊⠌⠑⠒⠔⠘⠡⠢⠤⠨⠰⡁⡂⡄⡈⡐⡠⢁⢂⢄⢈⢐⢠⣀⠇⠋⠍⠎⠓⠕⠖⠙⠚⠜⠣⠥⠦⠩⠪⠬⠱⠲⠴⠸⡃⡅⡆⡉⡊⡌⡑⡒⡔⡘⡡⡢⡤⡨⡰⢃⢅⢆⢉⢊⢌⢑⢒⢔⢘⢡⢢⢤⢨⢰⣁⣂⣄⣈⣐⣠⠏⠗⠛⠝⠞⠧⠫⠭⠮⠳⠵⠶⠹⠺⠼⡇⡋⡍⡎⡓⡕⡖⡙⡚⡜⡣⡥⡦⡩⡪⡬⡱⡲⡴⡸⢇⢋⢍⢎⢓⢕⢖⢙⢚⢜⢣⢥⢦⢩⢪⢬⢱⢲⢴⢸⣃⣅⣆⣉⣊⣌⣑⣒⣔⣘⣡⣢⣤⣨⣰⠟⠯⠷⠻⠽⠾⡏⡗⡛⡝⡞⡧⡫⡭⡮⡳⡵⡶⡹⡺⡼⢏⢗⢛⢝⢞⢧⢫⢭⢮⢳⢵⢶⢹⢺⢼⣇⣋⣍⣎⣓⣕⣖⣙⣚⣜⣣⣥⣦⣩⣪⣬⣱⣲⣴⣸⠿⡟⡯⡷⡻⡽⡾⢟⢯⢷⢻⢽⢾⣏⣗⣛⣝⣞⣧⣫⣭⣮⣳⣵⣶⣹⣺⣼⡿⢿⣟⣯⣷⣻⣽⣾⣿")
        
        for i in 0 ..< range.length {
            let char = string.character(at: range.location + i)
            rep += "\(chars[Int(char) % chars.count])"
        }
        if NSMakeRange(0, string.length).intersection(range) != nil {
            return string.replacingCharacters(in: range, with: rep)
        } else {
            return string as String
        }

//        if string.length <= range.upperBound {
//            return string.replacingCharacters(in: range, with: rep)
//        } else {
//            NSLog("\(string.length), \(range.upperBound)")
//            return string.replacingCharacters(in: NSMakeRange(range.location, string.length), with: rep)
//        }
    }
}

public extension String {
    var fixed: String {
        let str: String = self
        return str
    }
}

private let sharedDateFormatter = DateFormatter()
public func makeNewDateFormatter() -> DateFormatter {
    return sharedDateFormatter
}
