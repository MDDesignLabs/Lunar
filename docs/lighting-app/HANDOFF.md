# Hand-off: continue the hardware setup on the Mac

For a Claude session running **on the user's Mac** (Desktop app or `claude remote-control` in `~/lunar-lighting`). The earlier work ran in a cloud container with no hardware access; everything below the "done" line still needs doing on the real hardware.

**Read first:** `docs/lighting-app/PLAN.md`, `docs/lighting-app/VERDICT.md` (especially "Update: no Pro licence") and `lighting-prototype/README.md`.

## Setup facts

- **Hardware:** Mac Studio (Apple Silicon), macOS 26.7; AOC CU34G4Z; ESP32 + TSL2591 at `lunarsensor.local` (192.168.0.163, currently reading ~23 lx).
- **Lunar:** the Pro licence was an **expired demo**, so Sensor Mode is disabled and `lunar lux` returns `-1.0`. Lunar is out of the loop.
- **Configuration:** `BACKEND=m1ddc`, `LUX_SOURCE=direct`. Govee bars aren't bought yet, so `GOVEE_IPS=""` and probe 07 is skipped.
- **Monitor OSD:** User mode, R/G/B = 50/50/50. The baseline equals neutral.
- **Already built by probe 00:** m1ddc (stock) and m1ddc-1x. The Xcode licence has been accepted. The Command Line Tools are installed.
- **Wi-Fi:** the ESP32 shows about 33% ping loss and 160–270 ms round trips, probably ESPHome's Wi-Fi power saving. Probe 02 will show whether the event stream itself drops out.

## Rules the user set

1. **One app on the DDC bus.** Quit Lunar, BetterDisplay and MonitorControl before any probe, and before `lightd` runs. `lib/ddc.sh` refuses m1ddc writes while any of them is running.
2. **Conservative EEPROM limits** whatever probe 06 finds. Probe 06 Part B (pulling the power cord) is **skipped**. It's opt-in via `--with-power-cut`, and the user declined it.
3. **Walk through step by step.** The user is a product designer: explain each command before running it, and stop after anything that needs a physical action.
4. **If a result contradicts PLAN.md or VERDICT.md, say so explicitly.**

## Done

- **Probe 00 ran, but on an older version.** Rerun it after `git pull`. It now checks the licence first and builds `helpers/displaystate.swift` into `~/.lighting/tools/displaystate`. That helper has **never been compiled**, because the container had no `swiftc`. If it fails to build, fix it.
- **`lunar mode sensor --print-mapping` printed nothing.** The likely reason is that `Mode.run` never loads displays in a standalone CLI instance; `Displays`, `Get` and `Set` call `cliGetDisplays()` and `Mode` doesn't. The learned curve may still be in Lunar's saved settings; try:
  `defaults export fyi.lunar.Lunar - | python3 -c 'import plistlib,sys; d=plistlib.load(sys.stdin.buffer); print(d.get("displays"))'`
  (`plistlib` rather than `plutil -convert json`: the latter fails if any saved setting holds binary data.)
  Look for `sensorBrightnessMapping` (lux → brightness %) inside the display entries. If it's there, turn it into `BRIGHTNESS_CURVE`.

## Review notes on the recovered curve

This is the `BRIGHTNESS_CURVE` the local session derived from Lunar's saved settings.

1. **The pasted string had a malformed entry**: `134` with no colon. Print the raw `sensorBrightnessMapping` again and rebuild the string exactly. `lib/engine.awk` now skips malformed entries and sorts points, so a bad entry can't read as 0%, but the value should still be recovered.
2. **Most of it is probably Lunar's default starting curve, not two weeks of learning.**
   - On Apple Silicon, when a display has no curve yet, Lunar seeds `sensorBrightnessMapping` from `nitsToPercentageMapping` (`Display.swift:576–580`). That seed uses exactly these lux values, from `LUX_TO_NITS`: 0, 13, 23, 39, 71, 80, 100, 135, 160, 190, 224, 313, 565, 702, 800, 1000.
   - **Learned points are the ones whose lux value is NOT in that list.**
   - **Missing seed values show where a correction was made nearby**: Lunar deletes neighbours that would break ordering when it inserts a correction.
   - The recovered curve keeps every seed value from 100 lux up, and is missing 13–80. So the learning, if any, is in the low-light range.
   - Tell the user which points are learned and which are seed, rather than calling it all training.
   - **A quick test:** Lunar records a manual correction as a *new* point at the lux you were in, rounded to 4 decimals. So if the curve has exactly the 16 seed lux values and nothing else, Lunar probably never recorded a correction.
     - The y values then come from Lunar's own nits-to-percent conversion. That conversion is encrypted and not linear, so "the values are above a linear estimate" is not evidence of learning.
     - The one thing this can't rule out: the encrypted insert function (with its "cliff" parameters) might also adjust neighbouring points.
   - **Write the curve into `~/.lighting/config.sh` straight from the parsed data. Never retype or copy it from the chat:** the user's pastes of terminal output drop characters. Then check it by machine: every entry is `number:number`, lux values ascend, and the count matches the source.
3. **The targets are percentages of Lunar's min–max brightness range.** Check `minDDCBrightness` and `maxDDCBrightness` for the AOC in the same export. If they aren't 0 and 100, rescale before use.

## Probe 05: first run failed, and why

The first run measured flat readings close to the floor on every channel (≈2.6 lux). That was a flaw in the probe's design, not a hardware answer.

- **What went wrong:** the probe asked for Safari full screen and *then* an Enter press in Terminal. Switching to Terminal leaves Safari's full-screen Space, so the monitor showed the desktop, not the white page.
- **What changed:**
  - `helpers/whitepatch.swift` shows an always-on-top white window that holds whatever app has focus.
  - A ~40 s preflight (white vs black) stops the probe unless the sensor sees at least 20 lux of difference and 5× the black reading.
  - The display is kept awake (`caffeinate -d`).
  - Brightness is raised to 80 during the probe and restored afterwards.
  - The floor is re-measured before each channel.
  - Every probe now refuses to run while `lightd` is running.
- **Not yet verified on the Mac:** `whitepatch` has never been compiled (the cloud container has no `swiftc`). Rerun probe 00 or 05, and it builds automatically.
- **Discard** the first run's `05-gain-measurements.csv`.

## New from the research docs (2026-09-26)

`SPEC.md`, `BUILD_PLAN.md`, `TEST_PLAN.md` and `RESEARCH_01`–`06` are now in this folder. Two things they change for the hardware work:

- **Q9: report the transport facts first.** Run `system_profiler SPHardwareDataType | grep -E "Model (Name|Identifier)|Chip"`, note which port the AOC is plugged into (HDMI or USB-C/Thunderbolt), and paste `m1ddc display list detailed`. These decide the Swift DDC transport (chip address 0x37 or 0xB7; RESEARCH_02 §1.3).
- **Q8: the launchd agent may not reach the sensor.** Apple TN3179 says launchd *agents* aren't exempt from Local Network privacy (RESEARCH_04 §2). After `./install.sh`, check `~/.lighting/lightd.log` for live lux within a minute. If none arrive, run `lightd` from Terminal instead and tell the user. Don't try to work around the privacy check.

Also report probe 03 and 04 results (Q1, Q2, Q14). They were run, but the results haven't reached the docs yet.

## Review fixes (2026-09-26) that change the hardware steps

Six review agents checked the code, probes, tests and docs. What changed for you:

- **Probe 05:**
  - A click on the white screen now stops the probe and restores the monitor. Before, the probe carried on and measured the desktop, as in the failed first run.
  - It also stops after two readings in a row with no sensor data.
  - The white-screen helper is rebuilt automatically because its source changed. It still hasn't been compiled on a real Mac, so if `swiftc` fails, paste `probe/results/whitepatch-build.log`.
- **Probe 03** won't overwrite an existing baseline (use `--rebaseline` only if the monitor is really back at its original settings), and it accepts only numbers 0–100.
- **All probes** now also refuse to run while MonitorControl is running.
- **`light critical on`** now exits 1 and says why if neutral couldn't be written: another DDC app is running, or today's writes are used up. The override has its own reserve of 10 writes per channel beyond the daily cap (`OVERRIDE_RESERVE`), and the menu bar shows "NOT neutral" when it's incomplete.
- **Ask the user before probe 05:** does the ESP32 firmware set the TSL2591 to `gain: auto`? The repo's `Lunar/ALS/tsl2591.yaml` does. The reviewer's concern: dim steps may switch the sensor's gain range mid-probe and bias the corrected gain table by a few percent. It wouldn't flip the linear-vs-gamma verdict. Pinning `gain: medium` for the probe means reflashing, so it's the user's call. Don't reflash without asking.

## To do, in order

1. `git pull`, then `bash lighting-prototype/probe/00-setup.sh`. Check the licence line (should be INACTIVE) and the helper line (should be built).
2. Try to recover Lunar's learned curve (command above).
3. **Probe 03** (reads and baseline). The user types the OSD values.
4. **Probe 04** (does the AOC need writes sent twice?).
5. **Probe 05**, the key one: linear or gamma-encoded gains. It needs a dark room, with the TSL2591 held face-on to the centre of the screen and left in place. Explain how to place it before running, and how to put the sensor back afterwards.
6. **Probe 06, Part A only.**
7. **Probe 02 for 24 h, with Lunar quit and before installing** (so it measures a single client). Show the user how to check on it (`tail` the CSV) and how to stop it (Ctrl-C prints a summary).
8. `./install.sh`, then write `~/.lighting/config.sh` from the probe results and explain each value:
   - `M1DDC`: `m1ddc-1x` if probe 04 allows single writes
   - `GAIN_TABLE` and `GAIN_GAMMA` from probe 05
   - `CRITICAL_GAINS` = measured neutral
   - `BRIGHTNESS_CURVE` from Lunar's saved points if recovered
   - conservative intervals and caps (the example defaults already are)
9. Set up the SwiftBar plugin and a Shortcut running `bin/light critical toggle`, pinned to the menu bar with a keyboard shortcut. Optionally add `bin/light brighter` / `bin/light dimmer` shortcuts to replace Lunar's brightness keys.
10. Finish with:
    - a table of the seven open questions with measured answers
    - the corrected gain table
    - what to watch over the next week
    - a go/no-go on the Swift v1, and on buying Lunar Pro

Tests: `lighting-prototype/test/run_tests.sh` (82 checks, all passing (81 plus one SKIP on a machine with no multicast route), simulators only) runs anywhere, in about 3 minutes. Since 2026-09-26 it writes only to a temp folder: it no longer touches `probe/results/`, so running it after a probe is safe. (Before that fix it deleted that folder. If you ran the tests after a probe with an older checkout, check the results are still there.)
