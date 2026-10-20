import Cocoa
import TelegramCore
import Postbox
import SwiftSignalKit
import InAppSettings
import TGUIKit
import FilePanels
import TelegramTheme
import TelegramUtils
import FoundationUtils

public func saveAs(_ file:TelegramMediaFile, account:Account) {
    
    let name = account.postbox.mediaBox.resourceData(file.resource) |> mapToSignal { data -> Signal< (String, String), NoError> in
        if data.complete {
            var ext:String = ""
            let fileName = file.fileName ?? data.path.nsstring.lastPathComponent
            if let ext = file.fileName?.nsstring.pathExtension {
                return .single((data.path, ext))
            }
            ext = fileName.nsstring.pathExtension
            return resourceType(mimeType: file.mimeType) |> mapToSignal { _type -> Signal<(String, String), NoError> in
                let ext = _type == "*" || _type == nil ? (ext.length == 0 ? "file" : ext) : _type!
                
                return .single((data.path, ext))
            }
        } else {
            return .complete()
        }
    } |> deliverOnMainQueue
    
    _ = name.start(next: { path, ext in
        savePanel(file: path, ext: ext, for: mainWindow, defaultName: file.fileName)
    })
}

public func showInFinder(_ file:TelegramMediaFile, account:Account)  {
    let path = downloadFilePath(file, account.postbox) |> deliverOnMainQueue
    
    _ = combineLatest(queue: .mainQueue(), path, downloadedFilePaths(account.postbox)).start(next: { (expanded, paths) in
        
        guard let (boxPath, adopted) = expanded else {
            return
        }
        if let id = file.id {
            do {
                
                if let path = paths.path(for: id) {
                    let lastModified = Int32(FileManager.default.modificationDateForFileAtPath(path: path.downloadedPath)?.timeIntervalSince1970 ?? 0)
                    if fileSize(path.downloadedPath) == Int64(path.size), lastModified == path.lastModified {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path.downloadedPath)])
                        return
                    }
                
                }
                
                var adopted = adopted
                var i:Int = 1
                let deletedPathExt = adopted.nsstring.deletingPathExtension
                while FileManager.default.fileExists(atPath: adopted, isDirectory: nil) {
                    let ext = adopted.nsstring.pathExtension
                    adopted = "\(deletedPathExt) (\(i)).\(ext)"
                    i += 1
                }
                
                try? FileManager.default.copyItem(atPath: boxPath, toPath: adopted)
           
                let quarantineData = "does not really matter what is here".cString(using: String.Encoding.utf8)!
                _ = Int(strlen(quarantineData))
                
//                setxattr(adopted.cString(using: .utf8), "com.apple.quarantine", quarantineData, quarantineDataLength, 0, XATTR_CREATE)

                    // removexattr(adopted.cString(using: .utf8), "com.apple.quarantine", 0)

                
                let lastModified = FileManager.default.modificationDateForFileAtPath(path: adopted)?.timeIntervalSince1970 ?? FileManager.default.creationDateForFileAtPath(path: adopted)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
                
                let fs = fileSize(boxPath)
                let fileSize = fs ?? file.size ?? 0
                let path = DownloadedPath(id: id, downloadedPath: adopted, size: Int64(fileSize), lastModified: Int32(lastModified))
                
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: adopted)])
                _ = updateDownloadedFilePaths(account.postbox, {
                    $0.withAddedPath(path)
                }).start()
                
            }
        }
    })
}
