# Hand-off: continue the hardware setup on the Mac

For a Claude session running **on the user's Mac** (Desktop app or `claude remote-control` in `~/lunar-lighting`). The earlier work ran in a cloud container with no hardware access; everything below the "done" line still needs doing on the real hardware.

**Read first:** `docs/lighting-app/PLAN.md`, `docs/lighting-app/VERDICT.md` (especially "Update: no Pro licence") and `lighting-prototype/README.md`.

## Setup facts

- **Hardware:** Mac Studio (Apple Silicon), macOS 26.7; AOC CU34G4Z; ESP32 + TSL2591 at `lunarsensor.local` (192.168.0.163, currently reading ~23 lx).
- **Lunar:** the Pro licence was an **expired demo**, so Sensor Mode is disabled and `lunar lux` returns `-1.0`. Lunar is out of the loop.
- **Configuration:** `BACKEND=m1ddc`, `LUX_SOURCE=direct`. `GOVEE_IPS=""` until probe 07 saves the bars' addresses (below).
- **Monitor OSD:** User mode, R/G/B = 50/50/50. The baseline equals neutral.
- **Already built by probe 00:** m1ddc (stock) and m1ddc-1x. The Xcode licence has been accepted. The Command Line Tools are installed.
- **Work (2026-10-17):** UI/UX product design. Colour matters, but the target is sRGB/D65 screens, not print or grading. So RESEARCH_09 Q5 is "moderate": the screen's own white point matters far more than the bias light's CRI. Keep the Govee if probe 07 checks E, F and I pass; the DIY kit is optional. Open: whether the screen's white should follow the time of day as well as the room light. The blackout room is dark at noon too, so lux alone warms the screen to 5000 K during the working day.
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

## First live run (2026-10-11, lightd from Terminal)

From `bin/light writes`, `lightd.log` and `pgrep` that the user pasted:

- **Working on the real hardware:**
  - live lux from the ESP32;
  - brightness following it, with writes at least 60 s apart;
  - display sleep pausing writes, and wake reapplying once after 8 s (TEST_PLAN M-02);
  - neutral gains on exit (FR-45).
- **m1ddc write time:** 65–81 ms per write, with stock double send. That puts the three-gain override at about 0.4 s including the 100 ms gaps, well inside NFR-01's 2 s.
- **One lightd only.** `pgrep` shows three `bin/lightd` processes, but they're one lightd and its stream helpers: the main loop, the stream subshell and the `while read` subshell.
- **Probe 05 (second run) is in, and was re-analysed with the fixed script, giving the same result.** The gains act in linear light with a small offset (exponent 1.23), and there's no headroom above 50. Corrected table: `GAIN_TABLE="6500:50:50:50,6000:50:48:47,5500:50:46:43,5000:50:43:35,4500:50:40:27,4000:50:37:21"`, with `GAIN_GAMMA=1.23`. The room wasn't dark (white ≈ 2.2× black, so the preflight was skipped), but the verdict was checked to hold (RESEARCH_03 §2). Blue is the least certain channel; a darker rerun would tighten it.
- **Fixed after this run:**
  - a restart left gains neutral for up to 10 min, because the exit's neutral write started the gain interval. The first apply after start is now forced, like a wake;
  - a brightness write deferred by the interval wasn't retried once lux stopped moving. This log didn't hit it, because lux kept changing.
- **Running under launchd (Q8): works.** After `./install.sh`, the agent (pid matching `launchctl print`) received live lux that changed when the sensor was covered. That's against TN3179's expectation for agents; the reason is UNVERIFIED. **Confirmed after a reboot** with nothing started by hand: current lux, and `last sent` matching the target.
- **Restart cost:** each stop writes neutral and each start writes the warm gains back, so 2 writes per changing channel per restart. A day of testing with ~7 restarts used 14 of 30 on green and blue. On a normal day (at most one restart) that's ~2, well inside the budget.

## First update on the Mac (2026-10-11)

The `bin/light` on the Mac predates `bin/light update`, and the clone has local edits (the `[!]` in the prompt), so a plain `git pull` may refuse. Run this once from `~/lunar-lighting`:
```
git stash push -m "before first light update" && git pull --ff-only && lighting-prototype/bin/light update
```
After that, `bin/light update` is the only command needed. It trims `~/.lighting/config.sh` to personal overrides (with a dated backup), so the research curve, `BRIGHTNESS_MIN=0`, compensation off and the measured gain table come from the repo. The stash holds the old local edits; nothing deletes it.

## Daily review (from 2026-10-13)

- Each evening the user pastes `lighting-prototype/bin/light report`. Its output covers:
  - the config in effect;
  - an hourly table of lux, brightness sent, Kelvin and nudge, from lightd's 5-minute `samples-YYYY-MM-DD.csv`, kept 30 days;
  - the day's monitor writes, with brightness changes timed;
  - the day's events, including every nudge (logged as `user:`).
- Check it against RESEARCH_07's targets:
  - brightness at 0% only below ~10 lx;
  - no hunting (writes ≥ 60 s apart, and well under the caps);
  - nudges: two or more a day in the same lux range means the curve is wrong there;
  - Kelvin only stepping slowly.
- Propose changes as new repo defaults, so the user gets them with `bin/light update` and never hand-edits config.sh.

**Log of reviews**
- **2026-10-13** (partial day, 12:00–14:xx):
  - **Working as designed:** brightness held at 0% below 50 lx; no brightness writes needed (already 0); Kelvin rose 5000→5250 K as lux reached ~20; no nudges; no sensor dropouts.
  - **Gain writes:** 7 per changing channel, all from restarts (update, reload, a manual restart). Each costs 2 (neutral on exit, warm on start). On a normal day expect ~2.
  - **Open:** a midday reading of only ~5 lx is very low for daytime. Either the room was really that dark (blinds closed, no lamp), or the sensor isn't seeing the room (placement or facing). **Answered:** the room has blackout blinds and is usually dark even by day, so the readings are real and the sensor placement is fine. The user mostly works in a dark room, so the dark end of the curve (0%, the ~55 cd/m² floor) matters most; watch for "still too bright at night" (RESEARCH_07 §4).
  - **Later, blackout opened (14:39–14:48):** the room rose to 40–70 lx. Kelvin went to 6500 K, then settled at 6000 K. Brightness wrote 2, 100, 18, 1, 3, 16, 22 and 6, each ≥ 60 s apart. The 100 was the user's phone torch held on the sensor as a test, so it was the correct response, not a fault. No change needed; TAU_UP stays 8 s.
  - **Fixed:** the config clean-up was logged twice per update, because install.sh re-ran it.

## Govee arrived (2026-10-13)

The H6056 bars are here. The shell fixes are in (P0b-T02, T03, T05, T06; untested on hardware). The user's steps, in order:
- **Govee Home app:** add both bars on **2.4 GHz** Wi-Fi; each light → Settings → **LAN Control** on (it can take minutes to show). Note the model on the box (Q17). Reserve the bars' IPs on the router.
- **Mount the bars** per RESEARCH_08 §1a (2026-10-17): upright on the brackets behind the monitor, aimed at the wall and slightly up; no LED visible from the chair, no reflections on the screen. The user's Gemini answer was about a strip, and most of it doesn't apply to bars. Still open: the wall gap and the wall colour.
- `git pull` (or `bin/light update`), then **stop lightd**: `launchctl bootout gui/$(id -u)/com.lighting.lightd`.
- **Run `bash lighting-prototype/probe/07-govee.sh`** (≈ 30 min). Before checks E, F and R: room dark, the TSL2591 flat on the wall behind the monitor; a sheet of white paper for the ρ check; the phone for check I. Say "y" to saving `GOVEE_IPS`, `BIAS_CAL` and `BIAS_WALL_RHO`.
- Paste `probe/results/07-govee.txt` (the `RESULT Q7/Q17/Q18/Q19` lines) for review: watch check B ("brightness switches an off bar on"), check E (white path) and the % check F lands on.
- Start lightd again (`./install.sh`, or `bin/lightd` in Terminal), check `bin/light status` shows `bias: on …`, then add the bias lines to the soak (P0b-T08).

## Bias light and light bar (2026-10-11)

- **Govee:** the user bought what RESEARCH_08 identifies as the H6056 "Flow Plus" bars; confirm on the box. Plan in BUILD_PLAN Phase 0b. The order is:
  1. Govee Home app: Wi-Fi on 2.4 GHz, then switch on **LAN Control** for each bar.
  2. Run probe 07 on the real device.
  3. Make the prototype fixes: turn-off support, an absolute 5 cd/m² wall target, a Kelvin clamp, and discovery.
  4. Calibrate the wall, then soak.

  *Update 2026-10-13:* the fixes have landed (see "Govee arrived" above), so step 3 is done in code and the order is now app → probe 07 → soak.
- **Xiaomi light bar:** ask the user to read the model number on the label (Q20). The app only ever **asks**; it never switches the bar by itself (FR-80). Most likely it's remote-only, so the prompt is a reminder.

## Brightness curve (2026-10-11)

The user found the screen too bright in a dark room. RESEARCH_07 has the sources and the check:
- the current seed curve gives ~140–160 cd/m² in the dark, against a 20–36 research optimum;
- this monitor's backlight floor is ~55 cd/m² (KitGuru, colorimeter-measured).

Recommended config:
- `BRIGHTNESS_CURVE="0:0,10:0,50:1,100:7,200:17,300:22,500:31,1000:76,2000:100"`
- `BRIGHTNESS_MIN=0`
- `LUMINANCE_COMPENSATION=0`

- Optional: `probe/08-brightness.sh` (Q16). Part A measures how this unit's brightness setting maps to light (sensor flat on the screen, dark room) and prints a corrected `BRIGHTNESS_CURVE` if it differs from KitGuru's review; Part B (sensor at the bezel, lights off) says whether the screen lights the sensor. Run it after a few days on the new curve, in a dark room; at most 30 m1ddc writes, and it needs lightd stopped.

Ask the user to move the sensor to the top bezel, facing them. Then check self-illumination at night: compare the lux with a black screen and with a white screen.

## Updating (2026-10-11): `bin/light update`

The user's `~/.lighting/config.sh` was a hand-edited copy of an old example, so it pinned stale values (Lunar's seed curve, `GAIN_GAMMA=2.2`, …) and hid new defaults after `git pull`. Now:

- **One command:** `~/lunar-lighting/lighting-prototype/bin/light update`. It:
  - pulls fast-forward only, retrying the fetch 3 times. A diverged branch stops it with nothing changed;
  - stashes local edits to tracked files as `light update <date>`, and never drops or pops the stash. Untracked files and `probe/results` are untouched;
  - re-runs the new `bin/light`, then cleans config.sh down to overrides (backup `config.sh.bak-YYYYMMDD-HHMMSS` first);
  - reloads the launchd agent via `install.sh` if it's installed. If lightd runs in a Terminal, it says to restart it;
  - prints the new commits and what the clean-up removed and kept.
- **The measured gains are now repo defaults:** `GAIN_TABLE` and `GAIN_GAMMA=1.23` from probe 05 (RESEARCH_03 §2). So **the user never needs to hand-edit config.sh again for repo defaults.** Personal settings stay: any value the clean-up doesn't recognise, comments, `M1DDC=…m1ddc-1x`, `BACKEND`/`LUX_SOURCE=lunar`.
- **Removed:** values equal to the current default, an old default from any earlier `config.example.sh`, or Lunar's seed curve (with or without the corrupt `134`). Lines it can't parse (`$(…)`, multi-line) are left alone and listed.
- **A plain `git pull` without `update`:** lightd logs `config.sh overrides <KEY> with an old value; run bin/light update` at start.
- `install.sh` runs the same clean-up. A new install gets a header-only config.sh instead of a full copy.
- **UNVERIFIED on the Mac:**
  - `git stash` and the update as a whole have only run against temp repos on Linux (test §10);
  - the launchd reload is the same path as `install.sh`, which has run on the Mac;
  - the clean-up hasn't seen the user's real config.sh. Ask them to paste the update's output, and check the `kept` lines.

## Review fixes (2026-09-26) that change the hardware steps

Six review agents checked the code, probes, tests and docs. Every finding and its verdict is in `REVIEW_2026-09-26.md`. What changed for you:

- **Probe 05:**
  - A click on the white screen now stops the probe and restores the monitor. Before, the probe carried on and measured the desktop, as in the failed first run.
  - It also stops after two readings in a row with no sensor data.
  - The white-screen helper is rebuilt automatically because its source changed. It still hasn't been compiled on a real Mac, so if `swiftc` fails, paste `probe/results/whitepatch-build.log`.
- **Probe 03** won't overwrite an existing baseline (use `--rebaseline` only if the monitor is really back at its original settings), and it accepts only numbers 0–100.
- **All probes** now also refuse to run while MonitorControl is running.
- **`light critical on`** now exits 1 and says why if neutral couldn't be written: another DDC app is running, or today's writes are used up. The override has its own reserve of 10 writes per channel beyond the daily cap (`OVERRIDE_RESERVE`), and the menu bar shows "NOT neutral" when it's incomplete.
- **`GAIN_GAMMA` now defaults to 1.0** (it was a guessed 2.2) until probe 05 measures it. If `~/.lighting/config.sh` still has `GAIN_GAMMA=2.2` from the old example, change it to 1.0, or to the probe 05 value once measured. New optional keys have safe defaults from `config.example.sh`, so the user's config needn't list them: `KELVIN_FLOOR`, `OVERRIDE_RESERVE`, `USER_MIN_GAP_MS`, `WAKE_GAP`, `WAKE_DELAY`.
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

Tests: `lighting-prototype/test/run_tests.sh` (97 checks, all passing (96 plus one SKIP on a machine with no multicast route), simulators only) runs anywhere, in about 3 minutes. Since 2026-09-26 it writes only to a temp folder: it no longer touches `probe/results/`, so running it after a probe is safe. (Before that fix it deleted that folder. If you ran the tests after a probe with an older checkout, check the results are still there.)
