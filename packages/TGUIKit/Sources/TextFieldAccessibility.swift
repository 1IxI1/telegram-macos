import Cocoa

extension NSTextField {
    open override func accessibilityParent() -> Any? {
        return nil
    }
}
extension NSSecureTextField {
    open override func accessibilityParent() -> Any? {
        return nil
    }
}