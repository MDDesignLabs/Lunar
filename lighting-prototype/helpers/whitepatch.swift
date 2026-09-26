// whitepatch: covers every screen with a plain white window that stays on top of
// everything (screen-saver level, all Spaces), whatever app has focus. Probe 05 uses
// it so switching to Terminal can't take the white patch off the monitor.
// Click or press any key on it to abort; the probe notices it has gone and stops.
// It also quits by itself after <max-seconds> (default 1500), or if the probe that
// started it dies, so a killed probe can't leave the screen covered.
// Built by probe/00-setup.sh (and by probe 05 if missing or older than this file).
//
//   whitepatch [max-seconds]
import AppKit

// A borderless window can't become key by default, so key presses would never reach it.
final class PatchWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

let maxSeconds = Double(CommandLine.arguments.dropFirst().first ?? "") ?? 1500
let parent = getppid()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

var windows: [NSWindow] = []
for screen in NSScreen.screens {
    let w = PatchWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    w.level = .screenSaver
    w.backgroundColor = .white
    w.isOpaque = true
    w.hasShadow = false
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    w.setFrame(screen.frame, display: true)
    w.makeKeyAndOrderFront(nil)
    w.orderFrontRegardless()
    windows.append(w)
}

_ = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { _ in
    exit(0)
}

// Safety exits: time limit, and the parent probe going away (we get re-parented).
DispatchQueue.main.asyncAfter(deadline: .now() + maxSeconds) { exit(0) }
Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
    if getppid() != parent { exit(0) }
}

if #available(macOS 14.0, *) {
    app.activate()
} else {
    app.activate(ignoringOtherApps: true)
}
NSCursor.hide()
app.run()
