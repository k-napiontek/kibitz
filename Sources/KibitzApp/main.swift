import AppKit

// A menu bar agent: no dock icon, no main window. `.accessory` is the runtime
// half of LSUIElement in Info.plist, and both are needed.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
