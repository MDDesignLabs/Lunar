# Research 04: macOS app structure and frameworks

Status: research, 2026-09-26. Source tags:

- **[apple: …]**: Apple documentation JSON from `developer.apple.com/tutorials/data/documentation/…`, fetched 2026-09-26
- **[tn3179]**: Apple Technote TN3179, "Understanding local network privacy", fetched the same way
- **[code: …]**: this repo or local reference clones
- **UNVERIFIED**: not checked; each one says what would settle it

---

## 1. Frameworks and APIs

Availability below is taken from the fetched docs. Your Mac runs macOS 26.7 (probe 00), so every one of these is available.

| Need | API | Min macOS | Source |
|---|---|---|---|
| Menu bar item with a popover-style window | `MenuBarExtra` + `.menuBarExtraStyle(.window)` | 13.0 | [apple: swiftui/menubarextra; …/menubarextrastyle/window] |
| No Dock icon | `LSUIElement` Info.plist key, or `NSApplication.ActivationPolicy.accessory` | 10.0 / — | [apple: bundleresources/…/lsuielement; appkit/…/accessory] |
| Settings window | `Settings` scene | 11.0 | [apple: swiftui/settings] |
| Launch at login | `SMAppService.mainApp` | 13.0 | [apple: servicemanagement/smappservice/mainapp] |
| Observable state | Observation framework | 14.0 | [apple: observation] |
| SSE lux stream | `URLSession.bytes(from:delegate:)` returning `AsyncBytes`; the docs name properties that deliver text as async sequences | 12.0 | [apple: foundation/urlsession/bytes(from:delegate:)] |
| Wait for the network instead of failing | `URLSessionConfiguration.waitsForConnectivity` | 10.13 | [apple: …/waitsforconnectivity]; recommended by [tn3179] |
| Govee UDP (later) | `NWConnection`, `NWListener`, `NWParameters.udp` | 10.14 | [apple: network/…] |
| Event plumbing | `AsyncStream` | 10.15 | [apple: swift/asyncstream] |
| Logging | `Logger` | 11.0 | [apple: os/logger] |
| Mac sleep/wake, display sleep/wake | `NSWorkspace` `willSleep`/`didWake`/`screensDidSleep`/`screensDidWake` notifications | 10.6+ (screens) | [apple: appkit/nsworkspace/…] |
| Display changes | `CGDisplayRegisterReconfigurationCallback(_:_:)`, `CGDisplayIsAsleep(_:)`, `CGGetOnlineDisplayList(_:_:_:)` | 10.2–10.3 | [apple: coregraphics/…] |
| IORegistry walk | `IOServiceGetMatchingServices`, `IORegistryEntryCreateCFProperty` | 10.0 | [apple: iokit/…] |
| DDC I2C | `IOAVServiceCreateWithService`, `IOAVServiceReadI2C`, `IOAVServiceWriteI2C` | **private** | [code: MonitorControl bridging header, m1ddc] |
| Curve chart (later) | Swift Charts | 13.0 | [apple: charts] |

**Deployment target:** macOS 14. That gives you the Observation framework. It's only a problem if the app ever needs to run on an older Mac, and it doesn't.

UNVERIFIED: Swift `actor` semantics (the recommended DDC serialiser). It's a Swift 5.5 language feature and I didn't fetch its documentation this session. *Settles it:* the Swift book's "Concurrency" chapter.

UNVERIFIED (narrowed 2026-09-26): the exact `AsyncBytes` property for line-by-line text. The `…/asyncbytes/lines` page returned 404, but the `URLSession.AsyncBytes` docs link `AsyncLineSequence` and `AsyncCharacterSequence`, and both pages exist [apple: foundation/urlsession/asyncbytes]. So a line sequence exists; only the property name (`lines` is the likely one) is unchecked. *Settles it:* check Xcode autocompletion on `URLSession.AsyncBytes`.

---

## 2. Local network privacy: the finding that changes the shell plan

**What macOS automatically allows** [tn3179, quoted]:
> "macOS automatically allows local network access by: Any daemon started by launchd; Any program running as root; Command-line tools run from Terminal or over SSH, including any child processes they spawn. **The exception for launchd daemons doesn't apply to launchd agents.**"

Consequences:

1. **The probes run from Terminal, so they're exempt.** That's why you never saw a prompt. It corrects my earlier guidance that Terminal might prompt.
2. **`lightd` as installed by `install.sh` is a launchd *agent*** (`~/Library/LaunchAgents/com.lighting.lightd.plist` [code: `lighting-prototype/install.sh`]). With `LUX_SOURCE=direct`, its `curl` to `lunarsensor.local` is a local network operation.
   - [tn3179]: for other programs, "expect the system to block its local network operations until the user grants it the Local Network privilege".
   - [tn3179]: for an agent not installed via `SMAppService`, set `AssociatedBundleIdentifiers` in the launchd plist so macOS knows which app is responsible.
   - [tn3179]: "macOS fails to display the local network alert when a process with a very short lifespan performs a local network operation (FB16131937)".
   - UNVERIFIED what actually happens to a bash-script agent with no bundle on macOS 26.7. It may be blocked with no prompt. *Settles it:* after `./install.sh`, check `~/.lighting/lightd.log` for "sensor: no data" while `curl` works from Terminal.
3. **Workarounds for the shell phase**, least bad first:
   - (a) Run `lightd` from a Terminal window, which is exempt. Clunky, but provably allowed.
   - (b) Run it as a launchd **daemon**, which is exempt, as root.
     - UNVERIFIED: that IOAVService DDC works as root.
     - It changes the state-file paths.
     - A bug in a root process can do more damage.
   - (c) Accept that the shell can't read the sensor in the background. **This is the strongest argument yet for the native app.**
4. **For the Swift app:**
   - add `NSLocalNetworkUsageDescription` [apple: "Any app that uses the local network, directly or indirectly, should include this description … direct unicast or multicast connections"];
   - use `waitsForConnectivity` or retry, because the first operation may be denied before the user answers the alert [tn3179];
   - the multicast entitlement "isn't required on macOS" [tn3179].
   - Loopback isn't covered: UNVERIFIED either way. TN3179 defines a local network as one "associated with a broadcast-capable network interface"; loopback isn't mentioned.

---

## 3. Recommended structure

```
LightingApp (SwiftUI App, LSUIElement)
├── MenuBarExtra(.window) → MenuView         reads AppState (Observation)
├── Settings scene → SettingsView
└── AppState (@Observable, @MainActor)
     ├── LuxClient      URLSession.bytes → AsyncStream<LuxSample>, reconnect with backoff
     ├── Engine         PURE: filter, curve, Kelvin, gains, bias (port of engine.awk)
     ├── DDCWriter      actor: transport (0x37 / 0xB7, see RESEARCH_02), scheduler, caps, log
     ├── SystemEvents   NSWorkspace + CGDisplay callbacks → AsyncStream<SystemEvent>
     └── Store          JSON in ~/Library/Application Support/<app>/ (curve, table, counters, mode)
```

- **Only `DDCWriter` touches hardware.** `Engine` has no side effects and is unit-tested.
- **Config compatibility:** the app should read the prototype's `~/.lighting/config.sh` values once, as a migration (a hand-parsed `KEY=value` subset). That way calibration done in the shell phase carries over.

**Handing over from shell to app** [derived design; not built yet]:
- The prototype already refuses writes while named apps run (`OTHER_DDC_APPS` [code: `lib/ddc.sh`]). Add the app's process name to that list.
- The app must refuse to write while `~/.lighting/state/lightd.pid` names a live `lightd` [code: `probe/lib.sh` `lightd_running`].
- That gives **exactly one writer** at every step of the migration.

---

## 4. Distribution

- Not App Store: private API (Guideline 2.5.1) and the sandbox rule for Mac App Store apps (2.4.5) [src: App Review Guidelines, fetched 2026-09-26].
- **Signing and the Local Network grant** (corrected 2026-09-26: this was UNVERIFIED; TN3179 answers it). [tn3179]: the system tracks programs by their code signature, which is a problem for "ad hoc signed code (Xcode displays this as Sign to Run Locally)"; it advises signing with an Apple-issued code-signing identity.
  - **Consequence:** pick a real signing identity early, a free Apple ID personal team at minimum, not "Sign to Run Locally". Then check the grant persists: build twice and confirm System Settings → Privacy & Security → Local Network keeps it (BUILD_PLAN P1-T08).

---

## What not to build

- **An App Sandbox build.** It isn't possible with IOAVService.
- **A separate helper daemon or XPC service.** One process is enough. It would also add a second "responsible code" identity for Local Network.
- **AppKit windows,** beyond what `MenuBarExtra(.window)` and `Settings` give you.
- **A plugin system, multi-display support, Intel support.**
- **Sparkle updates, crash reporting or analytics.**
- **CoreData or SwiftData.** A JSON file is enough.

---

## Assumptions

| Assumption | If wrong |
|---|---|
| macOS 14+ only | If you ever need macOS 13, replace Observation with `ObservableObject`. About a day's work |
| One process can do DDC and networking under one Local Network grant | If the grant resets per build, every rebuild re-prompts. Irritating, not blocking. TN3179 says ad-hoc signing causes exactly this; a stable signing identity avoids it (§4) |
| The shell `lightd` can't reliably reach the sensor as a launchd agent | If it can, the shell phase can run unattended and the case for the app weakens. Test first (SPEC Q8) |
| DDC works from a non-root GUI app | That's how MonitorControl and m1ddc run; `m1ddc` ran fine as your user in probe 00 |
