# Research 05: Bias light (Govee protocol, alternatives)

Status: research, 2026-09-26. **No Govee hardware owned yet.** Source tags:

- **[code: …]**: `wez/govee-py` (`govee_led_wez/govee.py`) and `wez/govee-lan-hass`, cloned this session
- **[src: govee2mqtt]**: `wez/govee2mqtt/docs/LAN.md`, fetched 2026-09-26
- **UNVERIFIED**: not checked; each one says what would settle it

Govee's own guide (`app-h5.govee.com/user-manual/wlan-guide`) and its community site were **blocked** from this environment. Every packet format below therefore comes from two independent open-source implementations by the same author. Treat it as "works in the wild", not as the specification.

---

## 1. The LAN protocol

| Item | Value | Source |
|---|---|---|
| Discovery | Send `{"msg":{"cmd":"scan","data":{"account_topic":"reserve"}}}` to multicast `239.255.255.250:4001` | [code: `govee.py`, `_lan_poller`; `BROADCAST_ADDR`, `BROADCAST_PORT = 4001`] |
| Replies | Unicast to the sender's IP on **UDP 4002**, whatever the source port. Only one program per IP can bind it | [code: `LISTEN_PORT = 4002`]; [src: govee2mqtt]; [code: govee-lan-hass README "cannot run two different implementations … from the same IP"] |
| Commands | Unicast to `<device>:4003` | [code: `COMMAND_PORT = 4003`] |
| Scan reply fields | `ip`, `device`, `sku`, `bleVersionHard/Soft`, `wifiVersionHard/Soft` | [code: `_process_lan_scan`] |
| Power | `{"msg":{"cmd":"turn","data":{"value":1}}}` (0 = off) | [code: `govee.py` ~L429] |
| Brightness | `{"msg":{"cmd":"brightness","data":{"value":N}}}` | [code: ~L662] |
| Colour temperature | `{"msg":{"cmd":"colorwc","data":{"colorTemInKelvin":K, …}}}` | [code: ~L575–590] |
| RGB | `{"msg":{"cmd":"colorwc","data":{"color":{"r":…,"g":…,"b":…}}}}` | [code: ~L505] |
| Status | `{"msg":{"cmd":"devStatus","data":{}}}`. The reply includes `onOff`, `brightness`, `color`, `colorTemInKelvin` | [code: `_request_lan_status`, `_process_lan_status`] |

**Still unknown:**
- The valid **brightness** range. UNVERIFIED; the code passes a percentage.
- The valid **Kelvin range per model**. UNVERIFIED.
- *Settles both:* probe 07, once you own a strip.

**Behaviour notes from the implementer:**
- **Read-after-write isn't reliable:** "while the devices generally respond immediate to a control request, they don't reliably return the updated device state for several seconds" [code: govee-lan-hass README].
- **Multicast is fragile on Wi-Fi:** "multicast-UDP is not well supported by various routers, especially on WiFi enabled networks". Alternatives are explicit broadcast, or a DHCP-reserved IP with a unicast scan [src: govee2mqtt].
- **LAN Control has to be switched on per device** in the Govee Home app [code: govee-lan-hass README].

**macOS side:**
- Sending to the multicast group doesn't need a group join; replies arrive by unicast [derived from the table above].
- On macOS the multicast entitlement isn't required, but `NSLocalNetworkUsageDescription` is [RESEARCH_04 §2, tn3179].

**The prototype already implements all of this** [code: `lighting-prototype/lib/govee.sh`, `bin/govee`], and it's tested against a simulated strip on real UDP sockets [code: `test/fake_govee.py`, `test/run_tests.sh` §3].

---

## 2. How bright the bias light should be: an unresolved contradiction

- **Your brief:** about 10% of screen brightness.
- **What I could find:** web-search summaries attribute to SMPTE ST 2080-3 **both** "5 cd/m² absolute, D65" **and** "about 10% of peak white". The same summary contradicts itself, and I couldn't open the source pages (d65.org and Wikipedia were blocked). The standard itself is paywalled. **UNVERIFIED either way.**
- **Consequence:** don't hard-code 10%. The prototype's `BIAS_K` (strip % per screen nit) is a starting guess, calibrated by eye [code: `config.example.sh`].
- **Another unknown:** whether a Govee strip's brightness % is linear in light output. UNVERIFIED. *Settles it:* the TSL2591 pointed at the wall, stepping brightness 1–100.

---

## 3. Alternatives worth considering *before* buying Govee

| Option | Adaptive? | Colour-critical friendly? | Integration effort | Evidence |
|---|---|---|---|---|
| **Fixed D65, high-CRI bias strip, no control** | No | **Yes, by design**: constant and neutral | None | Product claims UNVERIFIED |
| Govee via LAN | Brightness + Kelvin | Only if pinned to 6500 K and colour-accurate | Prototype ready | §1. Govee's colour accuracy UNVERIFIED |
| Home Assistant Adaptive Lighting | Sun-based Kelvin/brightness, not screen-based | No (it follows the sun) | Needs HA | [src: basnijholt/adaptive-lighting README: "adjusts the brightness and color of your lights based on the sun's position"; defaults `min_color_temp 2000`, `max_color_temp 5500`] |

**Opinion (not a finding):**
- For a colour-critical desk, a **fixed neutral bias light** meets the override's goal without any code.
- A controllable strip only adds value if you want the bias to dim with the screen at night.
- Decide after two weeks of using the adaptive white point.

---

## What not to build

- **Screen-content colour sync** (ambilight). It's a different product and needs screen capture.
- **The Govee cloud API.** It adds keys, rate limits and a network dependency.
- **BLE control** (`govee-py` has `ble.py`). LAN is enough.
- **Any Govee code before you own a strip.** The prototype's version stays disabled (`GOVEE_IPS=""`).
- **Automatic discovery as the only path.** Always allow a manual IP [src: govee2mqtt].

---

## Assumptions

| Assumption | If wrong |
|---|---|
| wez's packet formats match current Govee firmware | Commands are ignored silently (UDP has no ack). Probe 07 catches it |
| Your router passes multicast between Wi-Fi and LAN | Discovery fails. Use a reserved IP and unicast |
| Nothing else on the Mac binds UDP 4002 | Discovery fails. HA and Homebridge Govee plugins on the same Mac would conflict |
| A bias light helps at all | You spend money on a nicety. It's cheap to test with a fixed strip first |
