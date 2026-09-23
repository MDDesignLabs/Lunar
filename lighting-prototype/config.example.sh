# Lighting prototype configuration.
# Copy to ~/.lighting/config.sh and edit. Plain shell: KEY=value, no spaces around '='.

# ── Backend ────────────────────────────────────────────────────────────────
# "lunar": Lunar Pro keeps adaptive brightness and owns the DDC bus; this
#          prototype adds white point, override and bias on top. Recommended
#          while you still have Lunar Pro installed. One app on the bus, and
#          Lunar re-applies gains after wake if reapplyColorGain is on.
# "m1ddc": no Lunar. This prototype does brightness too, writing DDC with m1ddc.
#          Quit Lunar (or unmanage the AOC in it) first.
BACKEND=lunar

LUNAR=~/.local/bin/lunar          # installed from Lunar → Settings → Install CLI
LUNAR_DISPLAY=external            # Lunar display filter: external | <serial> | <name without spaces>

M1DDC=/usr/local/bin/m1ddc
M1DDC_DISPLAY=""                  # e.g. "display 1" if you ever have more than one external display

# ── Lux source ─────────────────────────────────────────────────────────────
# "lunar": read via `lunar lux --listen` (only Lunar talks to the ESP32).
# "sse":   connect to the ESP32 directly.
LUX_SOURCE=lunar
SENSOR_URL=http://lunarsensor.local/events
SENSOR_ID=sensor-ambient_light
STALE_SECS=300                    # no sample this long → hold outputs, reconnect. 300 suits `lunar lux --listen` (emits only on change); 60 is enough for sse

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
BRIGHTNESS_MIN_INTERVAL=20        # seconds between adaptive brightness writes
BRIGHTNESS_DAILY_CAP=300
LUMINANCE_COMPENSATION=1          # raise backlight to offset the dimming from warm gains

# ── White point ────────────────────────────────────────────────────────────
KELVIN_DIM_LUX=10
KELVIN_DIM=5000
KELVIN_BRIGHT_LUX=300
KELVIN_BRIGHT=6500
KELVIN_STEP=250
KELVIN_MIN_INTERVAL=600           # seconds between adaptive gain sets
GAIN_DAILY_CAP=50                 # per channel
GAIN_GAP_MS=100                   # pause between the R, G and B writes in one set
# Kelvin:R:G:B calibration table. Measured points only. These are YOUR derived
# values and are UNVERIFIED until probe 05 tells you the AOC's gain domain.
# Replace with the table probe 05 prints.
GAIN_TABLE="6500:50:50:50,5500:50:47:44,5000:50:46:40,4500:50:44:36"
# The AOC's effective gain exponent (1.0 = linear light, 2.2 = gamma-encoded).
# Probe 05 measures it. Only used for luminance compensation.
GAIN_GAMMA=2.2

# ── Colour-critical override ───────────────────────────────────────────────
CRITICAL_GAINS="50:50:50"         # calibrated D65 neutral (R:G:B)
CRITICAL_BRIGHTNESS=40            # freeze backlight here; empty = leave brightness alone
RESTORE_LUNAR_MODE=sensor         # Lunar mode to go back to when the override ends

# ── Bias light (Govee LAN) ─────────────────────────────────────────────────
GOVEE_IPS=""                      # space-separated, e.g. "192.168.1.60 192.168.1.61"
MONITOR_NITS_MIN=40               # AOC CU34G4Z: measure or take from the spec sheet
MONITOR_NITS_MAX=350
BIAS_K=0.028                      # strip % per screen nit: a starting guess (350 nits → 10%). Calibrate by eye
BIAS_MIN=1
BIAS_MAX=40
BIAS_REFRESH=60                   # resend the current state this often (UDP has no ack)
