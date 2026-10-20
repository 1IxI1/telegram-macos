import Foundation
import OpusBinding

public final class DataItem : TGDataItem {
    let path: String
    public init(path: String) {
        self.path = path
        super.init()
    }
    public override func appendData(_ data: Data!) {
         do {
            if !FileManager.default.fileExists(atPath: self.path) {
                FileManager.default.createFile(atPath: self.path, contents: self.data(), attributes: nil)
            }
            let fileManager = try FileHandle(forWritingTo: URL(fileURLWithPath: self.path))
            fileManager.seekToEndOfFile()
            fileManager.write(data)
            fileManager.synchronizeFile()
            fileManager.closeFile()
        } catch {
            
        }
        super.appendData(data)
    }
}
