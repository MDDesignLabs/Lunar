# Lighting prototype (plan step 0)

Shell-only version of the adaptive display and lighting app: adaptive white point, bias light, colour-critical override and EEPROM-safe DDC writes. It also includes a probe kit that answers the plan's open hardware questions by measurement.

The verdict (how much of the app this delivers, and whether to build the Swift app) is in [`../docs/lighting-app/VERDICT.md`](../docs/lighting-app/VERDICT.md).

```
bin/lightd      adaptive loop (lux → filter → targets → rate-limited DDC + Govee). Runs under launchd
bin/light       one-shot control: critical on|off|toggle · kelvin <K> · neutral · bias · status · writes · update
bin/govee       Govee LAN API from the shell: discover · status · off-all · on/off · brightness · kelvin · rgb · raw
lib/            engine.awk (pure maths) · ddc.sh (write scheduler) · govee.sh + govee_udp.py (bias light) · apply.sh · common.sh · config_migrate.sh · update.sh
probe/          hardware measurements: run these first, on the Mac
swiftbar/       menu bar UI via SwiftBar (open source)
test/           simulators + test suite (runs anywhere: `test/run_tests.sh`)
```

Dependencies:

- macOS's own bash 3.2, awk, curl, nc and perl.
- python3 (comes with the Command Line Tools) for the Govee sockets (`lib/govee_udp.py`) and the probes. Without it, Govee sends fall back to nc and discovery hears one light only.
- m1ddc, built by `probe/00-setup.sh`, only for the `m1ddc` backend and the probes.
- The Lunar CLI, only for the `lunar` backend.
- SwiftBar, optional.

## 1. Probe your hardware first (about 1 hour of hands-on time plus a 24 h log)

Run these in Terminal, in order. Each writes `probe/results/NN-*.txt` ending in a `RESULT` line. That folder is git-ignored (it's your machine's data), and the test suite never touches it: tests write to a temp folder via `PROBE_RESULTS`. The probes refuse to run while Lunar, BetterDisplay, MonitorControl or `lightd` is running.

| Probe | Answers | Needs | Time |
|---|---|---|---|
| `probe/00-setup.sh` | Tools; builds m1ddc stock (2 writes) and `m1ddc-1x` (1 write); lists displays and sensor IDs | Command Line Tools | 3 min |
| `probe/01-cli-audit.sh` | **Audit 1–2:** does `lunar lux` read your ESP32? Does `lunar displays external blueGain` write VCP 0x1A? | Lunar running | 2 min |
| `probe/02-sensor-log.sh 24` | **Q6:** two SSE clients (this + Lunar) stable for 24 h? Also records your lux dataset (CSV) | Lunar running | 24 h, unattended |
| `probe/03-ddc-read.sh` | **Q2:** do reads work and match the OSD? **Q4a:** gain max. Records the baseline once; rerun with `--rebaseline` only if the monitor really is back at its original settings | Lunar quit | 2 min |
| `probe/04-single-write.sh` | **Q1:** does the AOC need every write sent twice? | Lunar quit | 2–5 min |
| `probe/05-gain-domain.sh` | **Q3:** linear-light or gamma-encoded gain? **Q4b:** headroom above 50? Prints what your gain rows *really* produce and a corrected `GAIN_TABLE`. The screen stays white ~16 min; click it to abort (the probe stops and restores the monitor) | Lunar quit, dark room, sensor taped to the screen | 16 min |
| `probe/06-persistence.sh` | **Q5:** what resets gains (sleep, input)? Part B (pulling the power cord) runs only with `--with-power-cut`, and is skipped for this setup | Lunar quit | 10 min |
| `probe/07-govee.sh` | **Q7, Q17, Q18, Q19:** checks A–I of RESEARCH_08 §5: discovery and device count, turn/brightness, Kelvin range, `devStatus`, white path (WW chips or RGB), the wall calibration (`BIAS_CAL`), wall reflectance ρ, packet gaps, Matter, flicker. Offers to save `GOVEE_IPS`, `BIAS_CAL` and `BIAS_WALL_RHO` to your config (backup first, dated comment). `--only FR` runs some checks; check F resumes if stopped. Puts the bars back as it found them | LAN Control on in the Govee app; lightd stopped; dark room and the TSL2591 on the wall for E, F, R | 30 min |
| `probe/08-brightness.sh` | **Q16 (optional, after a few days on the new curve):** Part A maps the brightness setting to light and compares it with KitGuru's review of this model; prints a `BRIGHTNESS_CURVE` from your own measurements. Part B checks the screen isn't lighting the sensor at its everyday spot. `--part-a-only` / `--part-b-only` skip a part. The screen stays white ~6 min, then ~1 min; click it to abort (the probe restores the monitor). At most 30 m1ddc writes | Lunar quit, dark room; sensor on the screen (A), then at the bezel (B) | 7 min |

How probe 05 works without a colorimeter:

1. It sets two of the three gains to 0 and shows a full-screen white page, so only one primary lights up.
2. Your TSL2591, taped to the screen, then sees a fixed spectrum. Its reading is proportional to that channel's output, whatever its spectral response.
3. Stepping that channel's gain from 50 to 20 gives the response curve.
4. The output ratio at gain 40 tells the two hypotheses apart: **0.80** means linear light, **0.61** means gamma-encoded.

## 2. Run it

```bash
./install.sh                     # creates ~/.lighting/config.sh (your overrides only), starts lightd under launchd
$EDITOR ~/.lighting/config.sh    # only what you change, e.g. GOVEE_IPS from probe 07. Defaults: config.example.sh
bin/light status
bin/light critical toggle        # the override
tail -f ~/.lighting/lightd.log ~/.lighting/writes.log
```

**Backends** (`BACKEND` in config):

- **`m1ddc` with `LUX_SOURCE=direct` (default).** No Lunar, no licence. Lux comes straight from the ESP32. The prototype does brightness from a log-lux curve, plus `light brighter` / `light dimmer` nudges that clear when the room light changes a lot. It also does the white point and the override. While Lunar, BetterDisplay or MonitorControl is running, every DDC write is refused and logged, so only one app ever touches the monitor. Display sleep/wake is detected by a small helper (`helpers/displaystate.swift`, built by probe 00). Without it, a 90 s gap in lux samples is the only wake signal.
- **`lunar` (needs an active Lunar Pro licence).** Lunar Pro keeps doing adaptive brightness, including its learning curve, and keeps owning the DDC bus. The prototype adds lux → Kelvin → gains, the override and the bias light. Gains are written as Lunar display properties, so with `reapplyColorGain` on (`lunar displays external reapplyColorGain true`), **Lunar's native wake handling re-applies your white point after sleep.** Only one app touches the monitor.

**Safety limits** (in `lib/ddc.sh`):

| Limit | Default |
|---|---|
| No-op skip | Never re-sends the last value |
| Brightness dead-band | 2 units |
| Minimum interval: brightness | 20 s |
| Minimum interval: gain set | 10 min |
| Daily cap: brightness | 300 |
| Daily cap: gains | 50 per channel |
| Write log | every attempt |

The override bypasses the intervals, never the caps or the no-op check.

## Bias light setup (Govee H6056)

1. **Govee Home app:** add both bars on **2.4 GHz** Wi-Fi, then each light → Settings → **LAN Control** on (the switch can take minutes to appear). Reserve their IPs in your router.
2. **Stop lightd**, then run `probe/07-govee.sh`. Answer "y" to save `GOVEE_IPS` (check A), `BIAS_CAL` (check F) and `BIAS_WALL_RHO` (the ρ check).
3. **Done:** restart lightd (`launchctl kickstart -k gui/$(id -u)/com.lighting.lightd`). `bin/light status` shows a `bias:` line.

What lightd then does (SPEC FR-60–FR-66, RESEARCH_08 §3): the bars light the wall to `BIAS_TARGET_NITS` (5 cd/m²) at the screen's Kelvin (clamped 2200–6500), 6500 K in colour-critical, and go **off** above `BIAS_OFF_LUX` (60 lx, back on below 40), when the display sleeps and when lightd stops. Until `BIAS_CAL` is measured they run at `BIAS_FALLBACK_PCT` (5 %, a guess). **Limit:** the shell has no pre-sleep hook, so a Mac sleep that isn't preceded by a display sleep (Apple menu → Sleep, closing the lid) leaves the bars on until wake. `GOVEE_IPS=""` turns all of it off.

## Updating

```bash
bin/light update
```

- **What it does:** `git pull --ff-only` on your branch (as a fetch, retried 3 times on network errors, then a fast-forward), then runs the new `bin/light` for the rest.
- **Config:** cleans `~/.lighting/config.sh` down to your own overrides, after a backup (`config.sh.bak-YYYYMMDD-HHMMSS`). It removes lines that repeat the current default, an old default or a superseded value (Lunar's seed curve, `GAIN_GAMMA=2.2`). It keeps everything else: comments, values it doesn't recognise, and lines it can't read safely. New defaults in `config.example.sh` then reach you with each update; you never edit config.sh for them.
- **lightd:** reloaded through `install.sh` if the launchd agent is installed. If you run it in a Terminal instead, it tells you to restart it.
- **Safety:** local edits to tracked files go into a `git stash` named `light update <date>` (`git stash list`, `git stash show -p`); it's never dropped or popped. Untracked and ignored files, such as `probe/results`, are never touched. If your branch has diverged from upstream, it stops and changes nothing. No reset, rebase or `--force`.
- After a plain `git pull` without `light update`, lightd logs `config.sh overrides <KEY> with an old value; run bin/light update` at start.

## 3. Menu bar and Shortcuts

**SwiftBar** (menu bar icon showing live Kelvin, the override toggle, and write counts):

```bash
brew install --cask swiftbar
ln -s "$PWD/swiftbar/lighting.10s.sh" ~/SwiftBarPlugins/      # or whichever folder SwiftBar uses
```

**Shortcuts** (an override on a hotkey, the Shortcuts menu, Siri or a Stream Deck):

1. Shortcuts → Settings → Advanced → **Allow Running Scripts**.
2. Create a new Shortcut with the action **Run Shell Script**: `/path/to/lighting-prototype/bin/light critical toggle`.
3. In Shortcut details, turn on **Pin in Menu Bar** and add a **keyboard shortcut**.
4. Optionally, a native-only chain with no scripts: Lunar's **Get Ambient Light (in lux)** → **If** / **Calculate** → Lunar's **Adjust Colors of a Screen (in hardware)** (R/G/B). This works as a one-shot. Shortcuts can't run it continuously; that's what `lightd` is for.

## 4. Known limits (all tested against simulators only)

- **Real hardware so far (2026-10-11):** the AOC and the ESP32 have run with lightd, under launchd and after a reboot. Probe 05 has run. The Govee bars arrived 2026-10-13; nothing has run on them yet (the bias code is tested against fakes only). `test/run_tests.sh` proves the logic, packet formats, rate limits and probe analysis against simulators: 200 checks, all passing (198 plus two SKIPs on a machine with no multicast route). The probes are what prove the hardware.
- **Local Network privacy (macOS 15+) may block `curl`/`nc` when started by launchd.** Apple's TN3179 exempts tools run from Terminal and launchd *daemons*, but says launchd *agents* (how `install.sh` runs `lightd`) are not exempt (docs/lighting-app/RESEARCH_04 §2). After installing, check that lux updates (`bin/light status`, twice); if it doesn't, run `bin/lightd` from Terminal instead. **On the author's Mac (macOS 26.7) the agent was not blocked** (2026-10-11); why is unverified, and a macOS update could change it. `LUX_SOURCE=lunar` sidesteps it for the sensor, because Lunar already has the permission. Govee UDP may still be blocked. If `lightd.log` shows Govee sends but the strips don't react under launchd while `bin/govee` works from Terminal, this is why.
- `lunar lux --listen` only emits when the value changes. In a perfectly steady room that looks like a stale sensor, and `lightd` reconnects every `STALE_SECS`. That's why the default `STALE_SECS` is 300; with `LUX_SOURCE=sse`, 60 is enough.
- **Daily write caps also bound the override, with a reserve.** Adaptive writes stop at `BRIGHTNESS_DAILY_CAP` / `GAIN_DAILY_CAP`. Writes back to neutral (the override, neutral on exit or after a crash) may use `OVERRIDE_RESERVE` more per channel. If even that is used up, or another DDC app is running, `light critical on` exits 1 and says why, and the menu bar shows "NOT neutral" instead of the override icon.
- White point has no learning. You edit the curve in config. Brightness learning comes from Lunar in `lunar` mode only.
