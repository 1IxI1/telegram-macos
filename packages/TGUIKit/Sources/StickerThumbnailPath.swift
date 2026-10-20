import Foundation

let decodingMap: [String] = ["A", "A", "C", "A", "A", "A", "A", "H", "A", "A", "A", "L", "M", "A", "A", "A", "Q", "A", "S", "T", "A", "V", "A", "A", "A", "Z", "a", "a", "c", "a", "a", "a", "a", "h", "a", "a", "a", "l", "m", "a", "a", "a", "q", "a", "s", "t", "a", "v", "a", ".", "a", "z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-", ","]
func decodeStickerThumbnailData(_ data: Data) -> String {
    var string = "M"
    data.forEach { byte in
        if byte >= 128 + 64 {
            string.append(decodingMap[Int(byte) - 128 - 64])
        } else {
            if byte >= 128 {
                string.append(",")
            } else if byte >= 64 {
                string.append("-")
            }
            string.append("\(byte & 63)")
        }
    }
    string.append("z")
    return string
}
