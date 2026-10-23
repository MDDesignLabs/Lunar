# Lighting prototype configuration: the repo defaults.
# Don't copy this file. lib/common.sh reads it first, then ~/.lighting/config.sh, which holds
# only the keys you change (plain shell: KEY=value, no spaces around '='). That way new
# defaults arrive with `bin/light update` (git pull + config clean-up).

# ── Backend ────────────────────────────────────────────────────────────────
# "m1ddc": no Lunar. This prototype does brightness AND white point, writing DDC
#          with m1ddc. Needs no licence. Lunar, BetterDisplay and MonitorControl must
#          not be running: while any of them is, every write is refused and logged.
# "lunar": needs an ACTIVE Lunar Pro licence. Lunar keeps adaptive brightness
#          (with its learned curve) and owns the DDC bus; this prototype adds white
#          point and the override on top, writing gains through Lunar's CLI.
BACKEND=m1ddc

LUNAR=~/.local/bin/lunar          # /Applications/Lunar.app/Contents/MacOS/Lunar install-cli
LUNAR_DISPLAY=external            # Lunar display filter: external | <serial> | <name without spaces>

M1DDC=~/.lighting/tools/m1ddc     # built by probe 00. m1ddc-1x (single write) if probe 04 allows
M1DDC_DISPLAY=""                  # e.g. "display 1" if you ever have more than one external display

# ── Lux source ─────────────────────────────────────────────────────────────
# "direct": connect to the ESP32 directly (same as "sse"). No Lunar needed.
# "lunar":  read via `lunar lux --listen`. Needs Lunar Pro: without it this returns -1.
LUX_SOURCE=direct
SENSOR_URL=http://lunarsensor.local/events
SENSOR_ID=sensor-ambient_light
STALE_SECS=60                     # no sample this long → hold outputs, reconnect. Use 300 with LUX_SOURCE=lunar (it only emits on change)

# ── Lux filter (log10 domain) ──────────────────────────────────────────────
TAU_UP=8                          # seconds, room getting brighter
TAU_DOWN=45                       # seconds, room getting darker
LUX_DEADBAND=0.04                 # log10 units (~10%) before anything is recomputed

# ── Sleep and wake ─────────────────────────────────────────────────────────
WAKE_GAP=90                       # seconds without a sample that may mean the Mac slept
WAKE_DELAY=8                      # after a wake, wait this long before touching DDC
SAMPLE_LOG_SECS=300               # lightd records lux and targets this often, for `light report`

# ── Brightness (m1ddc backend only; with Lunar, Lunar's own curve is used) ─
# lux:brightness% pairs, interpolated linearly in log10(lux).
# From docs/lighting-app/RESEARCH_07_BRIGHTNESS_CURVE.md: research luminance targets
# (20 cd/m2 in the dark up to the maximum at 2000 lux), inverted through KitGuru's
# colorimeter table for this monitor. UNVERIFIED on your unit: probe/08-brightness.sh checks it.
BRIGHTNESS_CURVE="0:0,10:0,50:1,100:7,200:17,300:22,500:31,1000:76,2000:100"
# 0, not 5: the hardware floor is already ~55 cd/m2 at 0%, and a floor of 5 would hold it at ~71.
BRIGHTNESS_MIN=0
BRIGHTNESS_MAX=100
BRIGHTNESS_DEADBAND=2             # DDC units
BRIGHTNESS_MIN_INTERVAL=60        # seconds between adaptive brightness writes (conservative)
BRIGHTNESS_DAILY_CAP=200          # hard fuse: adaptive brightness stops for the day after this
USER_MIN_GAP_MS=250               # user actions (nudges, override, presets): at most 4 writes/s per control
OFFSET_RESET_DECADES=0.5          # a brighter/dimmer nudge is dropped when lux moves ~3× away
# 1 = raise the backlight to offset the dimming from warm gains. Off by default: it only acts
# when the white point is warm, which is in dim light, where the goal is LESS light
# (RESEARCH_07 section 3). Set to 1 to turn it back on.
LUMINANCE_COMPENSATION=0

# ── White point ────────────────────────────────────────────────────────────
KELVIN_DIM_LUX=10
KELVIN_DIM=5000
KELVIN_BRIGHT_LUX=300
KELVIN_BRIGHT=6500
KELVIN_STEP=250
KELVIN_FLOOR=4000                 # never warmer than this, whatever the table or `light kelvin` asks
KELVIN_MIN_INTERVAL=600           # seconds between adaptive gain sets
# Time of day (SPEC FR-23, 2026-10-17). The room light decides how warm the screen gets, and
# the clock limits it:
#   - in the day the screen stays 6500 K however dark the room (true colours for design work);
#   - from sunset a dark room warms to KELVIN_DIM;
#   - from BEDTIME − 3 h it warms towards KELVIN_NIGHT, and stays there until the morning;
#   - it's back to 6500 K at sunrise, or at BEDTIME + 8 h if that's earlier.
# Each change ramps over TOD_RAMP_MIN. Sunrise and sunset come from the Mac's time zone
# (Europe/Berlin, Asia/Amman, …), so after a move the Mac's own time zone is enough.
# LATITUDE/LONGITUDE override the guess. TIME_OF_DAY=0 = room light only, as before.
TIME_OF_DAY=1
BEDTIME=23:00
KELVIN_NIGHT=4000
TOD_RAMP_MIN=60
LATITUDE=""
LONGITUDE=""
GAIN_DAILY_CAP=30                 # per channel (conservative)
GAIN_GAP_MS=100                   # pause between the R, G and B writes in one set
# Kelvin:R:G:B calibration table. Measured by probe 05 on this desk's AOC on 2026-10-11
# (docs/lighting-app/RESEARCH_03_COLOUR.md section 2): the gains act in linear light with a
# small offset, and 50 is the ceiling. The room wasn't dark; blue is the least certain channel.
GAIN_TABLE="6500:50:50:50,6000:50:48:47,5500:50:46:43,5000:50:43:35,4500:50:40:27,4000:50:37:21"
# The AOC's effective gain exponent (1.0 = linear light, 2.2 = gamma-encoded). Probe 05,
# 2026-10-11: 1.23 (RESEARCH_03 section 2). Only used for luminance compensation.
GAIN_GAMMA=1.23

# ── Colour-critical override ───────────────────────────────────────────────
CRITICAL_GAINS="50:50:50"         # calibrated D65 neutral (R:G:B). Adaptive gains never go above it
OVERRIDE_RESERVE=10               # writes per channel per day kept back for returning to neutral
                                  # (override, neutral on exit/crash) after the adaptive cap is hit
CRITICAL_BRIGHTNESS=40            # freeze backlight here; empty = leave brightness alone.
                                  # With BACKEND=lunar the override sets Lunar's per-display
                                  # "Adaptive brightness paused" first, so this write isn't
                                  # learned into Lunar's curve; turning the override off resumes it.

# ── Bias light (Govee LAN) ─────────────────────────────────────────────────
# docs/lighting-app/RESEARCH_08 sections 2–3, SPEC FR-60–FR-66. Setup: Govee app (2.4 GHz Wi-Fi,
# LAN Control on for each light), then probe/07-govee.sh, which offers to save GOVEE_IPS,
# BIAS_CAL and BIAS_WALL_RHO here in ~/.lighting/config.sh. Empty GOVEE_IPS = no bias light at all.
GOVEE_IPS=""                      # space-separated, e.g. "192.168.1.60 192.168.1.61" (the H6056 pair may be two lights)
GOVEE_K_MIN=2200                  # the H6056's rated white range (RESEARCH_08 section 1); nothing outside it is sent
GOVEE_K_MAX=6500
# Level: an absolute wall luminance, not tied to screen brightness. SMPTE ST 2080-3: the surround
# is 5.0 ± 0.5 cd/m2. On a matte wall that needs E = π × BIAS_TARGET_NITS / BIAS_WALL_RHO lux
# (≈ 19.6 lx at ρ 0.80), and the strip % for E comes from BIAS_CAL, the wall lux measured at each %.
BIAS_TARGET_NITS=5.0
BIAS_WALL_RHO=0.80                # a STARTING VALUE for white paint, until probe 07 measures your wall
BIAS_CAL=""                       # "pct:lux,…" from probe 07 check F (TSL2591 flat on the wall). Empty = not calibrated
# Used while BIAS_CAL is empty. UNVERIFIED: 400 lm on ~1 m2 of wall puts 5 cd/m2 near 3–8 %
# if the output is linear (RESEARCH_08 section 2), so 5 % is a guess at the low end. lightd logs
# once that the bias isn't calibrated.
BIAS_FALLBACK_PCT=5
BIAS_MAX=15                       # safety cap on the strip % whatever the table says (SPEC FR-62)
# The room decides: above BIAS_OFF_LUX (filtered) the room already lights the wall past 5 cd/m2,
# so the bars go off; back on below BIAS_ON_LUX. Starting values, UNVERIFIED (SPEC Q22).
BIAS_OFF_LUX=60
BIAS_ON_LUX=40
BIAS_IN_CRITICAL=on               # colour-critical override: on = 6500 K at the same level; off = bars off
BIAS_REFRESH=60                   # while on, resend brightness + Kelvin this often (UDP has no ack); never `turn 1`
GOVEE_MIN_INTERVAL=2              # seconds: at most one update this often (changes in between are coalesced)
GOVEE_GAP_MS=300                  # between datagrams to one bar (RESEARCH_08 section 3; 200 ms was UNVERIFIED)
# Philips Hue bias light (SPEC FR-68), e.g. the Hue Play Gradient Lightstrip for PC 32–34″.
# `bin/hue pair <bridge-ip>` saves HUE_BRIDGE and HUE_LIGHT in ~/.lighting/config.sh and the key
# in ~/.lighting/hue_key. When HUE_BRIDGE is set, Hue is the bias light and GOVEE_IPS is ignored.
HUE_BRIDGE=""
HUE_LIGHT=""
HUE_MIN_INTERVAL=1                # seconds between updates (the bridge takes ~10/s per light)
HUE_FADE_MS=2000                  # every change fades this long, done by the bridge
