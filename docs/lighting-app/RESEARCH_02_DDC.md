# Research 02: DDC on Apple Silicon (transport, wear, reliability)

Status: research, 2026-09-26. Source tags:

- **[code: …]**: source I read in this repo or in local clones of `MonitorControl/MonitorControl` (main, Sep 2026) and `waydabber/m1ddc` (main, Aug 2026)
- **[src: …]**: a fetched document
- **[derived]**: my own calculation
- **UNVERIFIED**: not checked; each one says what would settle it

---

## 1. The transport

### 1.1 Private API

Apple Silicon DDC goes through `IOAVService`, which isn't in any public SDK header. Both references declare it by hand [code: MonitorControl `*Bridging-Header.h`; m1ddc `headers/ioregistry.h`, `sources/i2c.m`]:

```c
typedef CFTypeRef IOAVService;
extern IOAVService IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IOAVServiceReadI2C(IOAVService service, uint32_t chipAddress, uint32_t offset, void* outputBuffer, uint32_t outputBufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVService service, uint32_t chipAddress, uint32_t dataAddress, void* inputBuffer, uint32_t inputBufferSize);
```

**Consequence:** App Review Guideline 2.5.1 says "Apps may only use public APIs" [src: developer.apple.com/app-store/review/guidelines, fetched 2026-09-26], and 2.4.5 requires Mac App Store apps to be sandboxed. **This app can't be distributed through the App Store.** For a personal tool that's fine.

UNVERIFIED: that the private symbols still exist and behave identically on macOS 26.7. Your probe 00 built m1ddc and listed the CU34G4Z, which shows the symbols link and the display is found. It doesn't yet prove writes land. *Settles it:* probe 03 and probe 04 results. They were run, but the results haven't been reported to this session.

### 1.2 Finding the right service

- **MonitorControl** walks the IORegistry. It pairs `AppleCLCD2`/`IOMobileFramebufferShim` entries with the next `DCPAVServiceProxy` whose `Location` is `External`, then scores each against each `CGDirectDisplayID` using EDID UUID fragments, IO location (+10), product name and serial [code: `MonitorControl/Support/Arm64DDC.swift`, `getIoregServicesForMatching`, `ioregMatchScore`].
- **m1ddc** does the same kind of search from the selected display's IO location [code: `m1ddc/sources/ioregistry.m:221–240`].
- **Lunar** builds a `DCP` object per `dispext`/DCP service with the same ingredients [code: `Lunar/Utils/DisplayController.swift:162`].

### 1.3 Chip address: a contradiction with PLAN.md

- **MonitorControl** always uses 7-bit chip address `0x37` with data address `0x51` [code: `Arm64DDC.swift`: `ARM64_DDC_7BIT_ADDRESS: UInt8 = 0x37`, `ARM64_DDC_DATA_ADDRESS: UInt8 = 0x51`].
- **m1ddc detects MCDP29xx-based ports** (provider class `AppleDCPMCDP29XX`) and routes DDC through **`0xB7`** for them, with a 50 ms read wait ("10 ms returned empty MCDP29xx replies in testing") [code: `m1ddc/sources/ioregistry.m:14–35, 251–253`; `headers/ioregistry.h:16`; `headers/i2c.h:26`].
- **Lunar also records `isMCDP`** per DCP [code: `DisplayController.swift`, `isMCDP = isMCDP29XX(dcpAvServiceProxy:)`].
- **MonitorControl's README says:** "DDC control using the built-in HDMI port of … all M1 Macs (MacBook Pro 14" and 16", Mac Mini, Mac Studio) … are not supported" [code: `MonitorControl/README.md:94`].
- **Contradiction:** PLAN.md §1.4 recommends porting MonitorControl's `Arm64DDC.swift`. **If your AOC is on an M1 Mac Studio's HDMI port, that transport won't work. Port m1ddc's transport selection (0x37 or 0xB7) instead.**
- UNVERIFIED:
  - which Mac Studio generation you have;
  - whether the AOC is on HDMI or USB-C/Thunderbolt (DisplayPort);
  - whether m1ddc chose `0xB7` for it.
  *Settles it:* `system_profiler SPHardwareDataType | grep Chip`, the physical port, and `m1ddc display list detailed`.

### 1.4 Packet format and timing

**Write** (m1ddc): `data[0]=0x84, data[1]=0x03, data[2]=VCP, data[3]=value>>8, data[4]=value&255, data[5]=0x6E ^ inputAddr ^ data[0..4]` [code: `m1ddc/sources/i2c.m`, `prepareDDCWrite`].

MonitorControl builds the same packet shape generically: `[0x80|(len+1), len, …, checksum]` [code: `Arm64DDC.performDDCCommunication`].

**Both send each write twice by default:**

| | Writes per command | Wait before each write | Read wait | Retries |
|---|---|---|---|---|
| m1ddc | `DDC_ITERATIONS 2` | `DDC_WAIT 10000` µs | 10 ms (50 ms on MCDP) | — |
| MonitorControl | `numOfWriteCycles ?? 2` | `writeSleepTime ?? 10000` | `readSleepTime ?? 50000` | `numOfRetryAttemps ?? 4` (spelling is theirs), with `retrySleepTime ?? 20000` |

[code: `headers/i2c.h:24–26`; `Arm64DDC.swift`]

**Blocking cost** [derived]: one m1ddc write is at least 2 × 10 ms of sleeps plus I2C time, so 20–50 ms. A read adds a 10–50 ms wait. That's why no transaction may run on the main thread. **Lunar breaks this rule:** `DDC.sync` is `mainThread(action)` [code: `Lunar/DDC/DDC.swift:857`].

UNVERIFIED: that the AOC needs the double send. *Settles it:* probe 04.

---

## 2. Reliability patterns worth copying

| Pattern | Where | Detail |
|---|---|---|
| Latest-value-wins coalescing, skip if unchanged | [code: MonitorControl `Model/OtherDisplay.swift:380–405`] | `writeDDCNextValue[command]` overwritten; write skipped when equal to `writeDDCLastSavedValue` |
| Serial DDC queue | [code: `OtherDisplay.swift:12` `writeDDCQueue`; `DisplayManager.globalDDCQueue`] | One transaction at a time |
| Sleep/reconfigure gating | [code: MonitorControl `Support/AppDelegate.swift:144–196`; `OtherDisplay.swift:381`] | Writes refused while `sleepID != 0 \|\| reconfigureID != 0`; driven by `NSWorkspace` sleep/wake notifications |
| Fault counters → stop writing | [code: `Lunar/DDC/DDC.swift:18–20, 1230–1260`] | `MAX_WRITE_FAULTS = 20`, `MAX_READ_FAULTS = 10`; a write over `MAX_WRITE_DURATION_MS = 2000` counts as severity 4 |
| Wait after wake | [code: `DDC.swift:818–836`] | `waitAfterWakeSeconds`, `delayDDCAfterWake` |
| Re-apply gains after wake | [code: `Lunar/AppDelegate.swift:1719, 2491–2497`] | Repeats `wakeReapplyTries` times, 2 s apart. That's a wear multiplier |

The prototype already does coalescing (no-op skip), a dead-band, minimum intervals, daily caps, a cross-process lock, a write log, and a refusal to write while another DDC app runs [code: `lighting-prototype/lib/ddc.sh`].

---

## 3. System events (public APIs, verified in Apple docs)

[src: developer.apple.com documentation JSON, fetched 2026-09-26]

| API | macOS | Use |
|---|---|---|
| `NSWorkspace.willSleepNotification` / `didWakeNotification` | availability not listed in the fetched JSON | Mac sleep/wake |
| `NSWorkspace.screensDidSleepNotification` / `screensDidWakeNotification` | 10.6+ | Display sleep/wake while the Mac is awake |
| `CGDisplayRegisterReconfigurationCallback(_:_:)` | 10.3+ | Resolution, arrangement, connect/disconnect |
| `CGDisplayIsAsleep(_:)` | 10.2+ | Polling check. The prototype's `helpers/displaystate.swift` uses it; **it compiled and ran on your Mac** (probe 00) |
| `CGGetOnlineDisplayList(_:_:_:)` | 10.2+ | "Displays that are online (active, mirrored, or sleeping)" |

---

## 4. EEPROM wear

**What's known:**
- Monitors keep settings in some non-volatile store. **Which one the AOC uses (EEPROM chip, MCU flash, or something else) is unknown.** UNVERIFIED, and not settleable without the service manual or a teardown.
- The "~100k cycles" figure comes from your brief. I couldn't fetch any EEPROM datasheet (the vendors' domains were blocked), so I can't cite typical endurance. UNVERIFIED.

**What the software can bound:**
- Probe 06 Part B brackets the delay between a write and its commit, by pulling the power cord at 1, 30 and 60 s. **You chose to skip it.** That leaves the worst case: every write costs a cycle.

**Budget under the worst case** [derived; conservative defaults in `config.example.sh`]:

| Output | Limit | Writes/day at the cap | Years to 100k at the cap | Realistic writes/day (estimate) |
|---|---|---|---|---|
| Brightness | ≥ 60 s apart, Δ ≥ 2, cap 200/day | 200 | 1.4 | 20–60 → 4.5–14 years |
| Each gain channel | set ≥ 600 s apart, cap 30/day | 30 | 9.1 | 5–15 → 18–55 years |

**Brightness is the binding constraint, not gains.** This contradicts the brief's intuition that "three gain writes per adjustment multiply" wear: gains are written roughly 10× less often per channel.

UNVERIFIED: the realistic daily counts. *Settles it:* a week of `writes.log` from the prototype.

**The double send, per probe 04's result:**
- If the AOC takes single writes, `m1ddc-1x` halves bus traffic.
- Whether it also halves *EEPROM* commits is UNVERIFIED: a monitor might commit once per identical pair.

---

## 5. Coexistence: one app on the bus

**Known DDC clients on your Mac:** Lunar (free, not running), BetterDisplay (installed, must stay closed), MonitorControl (not installed), and the prototype.

- The prototype refuses writes while `Lunar`, `BetterDisplay` or `MonitorControl` run [code: `lib/ddc.sh` `other_ddc_app`].
- All probes refuse to run while `lightd` runs, checked by PID file [code: `probe/lib.sh` `lightd_running`].

UNVERIFIED: what goes wrong when two clients interleave transactions. There's no source; the rule is precautionary.

---

## What not to build

- **An Intel DDC path.** You have Apple Silicon.
- **Multi-display matching logic.** One AOC. Keep MonitorControl's scorer only as a reference.
- **Smooth-transition DDC stepping** (§2, Lunar). It multiplies writes.
- **Repeated wake re-applies** (Lunar's `wakeReapplyTries`). One reapply after a settle delay is enough.
- **Read-modify-write** (`m1ddc chg …`). Always write absolute values from your own state.
- **DDC on the main thread.**
- **Hand-rolled DDC/CI "capabilities string" parsing.** Nothing in the spec needs it.

---

## Assumptions

| Assumption | If wrong |
|---|---|
| The AOC is on USB-C/DisplayPort, or on an HDMI port that m1ddc handles at 0xB7 | If it's on an HDMI port no open tool supports, only BetterDisplay (closed) can drive it: the native plan fails at the transport |
| Private `IOAVService` calls keep working on future macOS | An OS update can break the app with no warning. m1ddc/MonitorControl issue trackers are the early warning |
| Worst-case "every write commits" | Only makes the plan safer |
| The AOC accepts 0 as a gain (probe 05 relies on it) | Probe 05's channel isolation fails; the preflight would catch a dark screen, not a partly lit one |
