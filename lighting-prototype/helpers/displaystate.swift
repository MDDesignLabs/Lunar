// displaystate: prints "asleep" or "awake" for the external display(s).
// lightd calls this on every lux sample so it can (a) skip DDC writes while the
// monitor sleeps and (b) re-apply once when it wakes: the case a shell script can't
// otherwise see, because on a desktop Mac the display sleeps while the Mac stays awake.
// Built by probe/00-setup.sh with the Command Line Tools' swiftc.
import CoreGraphics
import Foundation

var ids = [CGDirectDisplayID](repeating: 0, count: 16)
var count: UInt32 = 0
// "Online" includes sleeping displays; a powered-off or unplugged monitor drops out.
guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success, count > 0 else {
    print("asleep")
    exit(0)
}
let online = Array(ids.prefix(Int(count)))
let external = online.filter { CGDisplayIsBuiltin($0) == 0 }
let targets = external.isEmpty ? online : external
print(targets.allSatisfy { CGDisplayIsAsleep($0) != 0 } ? "asleep" : "awake")
