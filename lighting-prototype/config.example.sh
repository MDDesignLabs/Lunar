# Lighting prototype configuration.
# Copy to ~/.lighting/config.sh and edit. Plain shell: KEY=value, no spaces around '='.

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

# ── Brightness (m1ddc backend only; with Lunar, Lunar's own curve is used) ─
# lux:brightness% pairs, interpolated linearly in log10(lux).
BRIGHTNESS_CURVE="0:10,10:20,40:35,100:50,300:70,1000:100"
BRIGHTNESS_MIN=5
BRIGHTNESS_MAX=100
BRIGHTNESS_DEADBAND=2             # DDC units
BRIGHTNESS_MIN_INTERVAL=60        # seconds between adaptive brightness writes (conservative)
BRIGHTNESS_DAILY_CAP=200          # hard fuse: adaptive brightness stops for the day after this
OFFSET_RESET_DECADES=0.5          # a brighter/dimmer nudge is dropped when lux moves ~3× away
LUMINANCE_COMPENSATION=1          # raise backlight to offset the dimming from warm gains

# ── White point ────────────────────────────────────────────────────────────
KELVIN_DIM_LUX=10
KELVIN_DIM=5000
KELVIN_BRIGHT_LUX=300
KELVIN_BRIGHT=6500
KELVIN_STEP=250
KELVIN_FLOOR=4000                 # never warmer than this, whatever the table or `light kelvin` asks
KELVIN_MIN_INTERVAL=600           # seconds between adaptive gain sets
GAIN_DAILY_CAP=30                 # per channel (conservative)
GAIN_GAP_MS=100                   # pause between the R, G and B writes in one set
# Kelvin:R:G:B calibration table. Measured points only. These are YOUR derived
# values and are UNVERIFIED until probe 05 tells you the AOC's gain domain.
# Replace with the table probe 05 prints.
GAIN_TABLE="6500:50:50:50,5500:50:47:44,5000:50:46:40,4500:50:44:36"
# The AOC's effective gain exponent (1.0 = linear light, 2.2 = gamma-encoded).
# Probe 05 measures it. Only used for luminance compensation.
GAIN_GAMMA=2.2

# ── Colour-critical override ───────────────────────────────────────────────
CRITICAL_GAINS="50:50:50"         # calibrated D65 neutral (R:G:B). Adaptive gains never go above it
OVERRIDE_RESERVE=10               # writes per channel per day kept back for returning to neutral
                                  # (override, neutral on exit/crash) after the adaptive cap is hit
CRITICAL_BRIGHTNESS=40            # freeze backlight here; empty = leave brightness alone.
                                  # With BACKEND=lunar the override sets Lunar's per-display
                                  # "Adaptive brightness paused" first, so this write isn't
                                  # learned into Lunar's curve; turning the override off resumes it.

# ── Bias light (Govee LAN) ─────────────────────────────────────────────────
GOVEE_IPS=""                      # space-separated, e.g. "192.168.1.60 192.168.1.61"
MONITOR_NITS_MIN=40               # AOC CU34G4Z: measure or take from the spec sheet
MONITOR_NITS_MAX=350
BIAS_K=0.028                      # strip % per screen nit: a starting guess (350 nits → 10%). Calibrate by eye
BIAS_MIN=1
BIAS_MAX=40
BIAS_REFRESH=60                   # resend the current state this often (UDP has no ack)
