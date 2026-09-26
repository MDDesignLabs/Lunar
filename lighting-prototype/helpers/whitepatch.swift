// whitepatch: covers every screen with a plain white window that stays on top of
// everything (screen-saver level, all Spaces), whatever app has focus. Probe 05 uses
// it so switching to Terminal can't take the white patch off the monitor.
// Click or press any key on it to abort. The probe kills it when done.
// Built by probe/00-setup.sh (and by probe 05 if missing) with the Command Line Tools' swiftc.
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

var windows: [NSWindow] = []
for screen in NSScreen.screens {
    let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    w.level = .screenSaver
    w.backgroundColor = .white
    w.isOpaque = true
    w.hasShadow = false
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    w.setFrame(screen.frame, display: true)
    w.orderFrontRegardless()
    windows.append(w)
}

_ = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { _ in
    exit(0)
}
app.activate(ignoringOtherApps: true)
NSCursor.hide()
app.run()
