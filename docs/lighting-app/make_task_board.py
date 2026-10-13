#!/usr/bin/env python3
"""Generates TASK_BOARD.md and tasks.csv (next to this file) from one task list.
   Edit the list below, then run: python3 docs/lighting-app/make_task_board.py"""
import csv, collections, pathlib

OUT = pathlib.Path(__file__).resolve().parent

# id, phase, title, type (primary[/secondary]), requires, deps, done-when, lo, hi, difficulty, status, source
T = []
def t(*a): T.append(a)

R = "routine"; NR = "needs research"; GH = "genuinely hard"
BP = "BUILD_PLAN"; NEW = "new (implied by SPEC/R06/TEST_PLAN)"

# ── Phase 0: calibrate and live with the shell system
t("P0-T01","0","Report probe 03 and 04 results","Hardware","Mac, AOC OSD, the results files","—","Q1, Q2, Q14 answered in SPEC §7 with values",0.25,0.5,R,"Run; results not reported",BP)
t("P0-T02","0","Mac Studio chip + AOC port + `m1ddc display list detailed` (Q9)","Hardware","Mac, a look at the cable","—","Chip, port and chip address (0x37/0xB7) recorded",0.25,0.5,R,"To do",BP)
t("P0-T03","0","Probe 05: gain domain (Q3, Q4)","Hardware","Dark room, sensor on the screen","P0-T01","RESULT Q3 present, drift < 3%",1,3,NR,"Done 2026-10-11: linear light, no headroom",BP)
t("P0-T03b","0","Re-analyse probe 05's CSV with the fixed analysis; compare with the first verdict","Hardware / Backend","The CSV, `git pull`","P0-T03","Both analyses agree, or the difference is explained; GAIN_TABLE and GAIN_GAMMA chosen",0.25,0.5,R,"Done 2026-10-11: both agree",NEW)
t("P0-T04","0","Probe 06 Part A: what resets gains (Q5)","Hardware","Mac, monitor buttons","P0-T01","KEPT/RESET for sleep, input, power",0.5,0.5,R,"To do",BP)
t("P0-T09","0","Probe 02: 24 h sensor log (Q6), Lunar quit","Hardware","ESP32 powered, Mac awake 24 h","—","RESULT Q6; lux CSV saved",0.5,0.5,R,"To do",BP)
t("P0-T10","0","Optional: reflash ESP32 with `power_save_mode: none` (Q12)","Hardware (firmware)","ESPHome toolchain, USB cable","P0-T09","Second probe 02 compared with the first",1,4,NR,"Optional",BP)
t("P0-T05","0","Write `~/.lighting/config.sh` from the results","Backend (config)","Probe results","P0-T01, P0-T02, P0-T03b, P0-T04","Every value has a comment saying where it came from",1,2,R,"Done 2026-10-12: measured gains + research curve are repo defaults (`light update`); M1DDC waits on probe 04",BP)
t("P0-T06","0","Install lightd; test Local Network as an agent (Q8)","DevOps","`./install.sh`, launchd","P0-T05, P0-T09","Lux updating under launchd for 1 h, or Q8 marked blocked with evidence",0.5,2,NR,"Done 2026-10-11: works under launchd, also after a reboot",BP)
t("P0-T07","0","If blocked: Terminal session or launchd daemon workaround","DevOps","launchd, possibly root","P0-T06","lightd runs unattended across logout/login",2,6,GH,"Not needed: P0-T06 passed",BP)
t("P0-T08","0","SwiftBar item + override Shortcut with a hotkey","Frontend (shell UI)","SwiftBar, Shortcuts app","P0-T06 (or P0-T07)","Override toggles from menu bar and hotkey in < 2 s",1,2,R,"To do",BP)
t("P0-T11","0","One-week soak of the shell system","QA","The daily soak checklist (TEST_PLAN §5)","P0-T05, P0-T06, P0-T08","7 days logged",1.75,1.75,R,"In progress: started 2026-10-12",BP)
t("P0-T12","0","Apply the research brightness curve to ~/.lighting/config.sh","Product / Backend (config)","RESEARCH_07 §3, the config file","P0-T05","Curve, BRIGHTNESS_MIN=0, LUMINANCE_COMPENSATION=0 and MONITOR_NITS 55/372 in config.sh; lightd restarted; sensor on the top bezel",0.25,0.25,R,"Done 2026-10-12 (`light update`)",NEW)
t("P0-T13","0","Probe 08: brightness response + self-illumination (Q16)","Hardware","Dark room; sensor on the screen (Part A), then at the bezel (Part B)","P0-T12","RESULT Q16a (curve matches KitGuru, or a measured BRIGHTNESS_CURVE) and RESULT Q16b (negligible or significant)",0.5,1,R,"Optional",NEW)
t("PM-01","0","Set weekly hours (Q15); re-baseline the schedule","Product","Your calendar","—","BUILD_PLAN totals converted to dates",0.5,1,R,"To do",NEW)
t("PM-02","0","Decide the darkening-latency target (NFR-02: accept ~210 s or faster TAU_DOWN)","Product","SPEC NFR-02","—","NFR-02 and US-1 AC1 updated",0.25,0.5,R,"To do",NEW)
t("PM-03","0","Close SPEC open questions as probes report (Q1–Q6, Q8, Q9, Q12, Q14)","Product","Probe results","P0-T01…P0-T09","SPEC §7 has an answer or a blocker for each",0.5,1,R,"In progress: Q3, Q4, Q8 answered",NEW)
t("PM-04","0","D0 review after 2 weeks: stop, or build the app; colorimeter","Product","Soak log, probe results","P0-T11","Decision written into BUILD_PLAN D0",1,2,R,"To do",NEW)

# ── Phase 0b: bias light (Govee H6056) and desk light bar (Xiaomi) in the shell, now (added 2026-10-11)
t("P0b-T01","0b","Govee setup: confirm the model (Q17), 2.4 GHz Wi-Fi, LAN Control on per light, DHCP reservations","Hardware","Govee Home app, router admin","—","Model in SPEC Q17; LAN Control on; IPs reserved and in GOVEE_IPS",0.25,1,R,"To do",BP)
t("P0b-T02","0b","Prototype Govee fixes: turn-off, Kelvin clamp 2200–6500, multicast join + unicast scan, sender address when `ip` is missing, `govee status`/`off-all`","Backend","lib/govee.sh, test/fake_govee.py","—","New tests pass for each fix",3,6,NR,"Done 2026-10-13 (code; untested on hardware)",BP)
t("P0b-T03","0b","Extend probe 07 to checks A–I (R08 §5)","Hardware / Backend","probe/07-govee.sh","P0b-T02","Writes RESULT Q7, Q17, Q18 and a BIAS_CAL line",1.5,3,R,"Done 2026-10-13 (code; untested on hardware)",BP)
t("P0b-T04","0b","Run probe 07 on the bars (was P8-T01)","Hardware","Dark room, sensor at the wall","P0b-T01, P0b-T03","Q7, Q17, Q18, Q19 answered or blocked with evidence",1,2,NR,"To do",BP)
t("P0b-T05","0b","Absolute bias level: BIAS_TARGET_NITS + BIAS_WALL_RHO + BIAS_CAL replace BIAS_K; calibrate to 5 cd/m²","Backend (config) / Hardware","Probe 07 check F, white paper for ρ","P0b-T04","Wall reads π·5/ρ lx ± 10 % at night (US-7 AC1)",2,4,NR,"Done 2026-10-13 (code; untested on hardware)",BP)
t("P0b-T06","0b","Bias colour and off states: follow screen K, 6500 K override, off for display sleep, clean stop, bright room; pre-sleep hook","Backend","lightd, sleepwatcher or the display-state helper","P0b-T02","US-7 AC2, AC3, AC5 on hardware",2,5,NR,"Done 2026-10-13 (code; untested on hardware)",BP)
t("P0b-T07","0b","BIAS_OFF_LUX (Q22): wall vs bezel lux at 4 times of day","Hardware","The sensor, moved between wall and bezel","P0b-T05","BIAS_OFF_LUX/BIAS_ON_LUX set; Q22 answered",0.5,1,R,"To do",BP)
t("P0b-T08","0b","Bias soak, 7 days, with the shell soak","QA","Soak checklist + bias lines","P0b-T05, P0b-T06","7 days: off by day, on at night, off after sleep, never stuck on",0.5,1,R,"To do",BP)
t("PM-08","0b","D0b: keep the Govee for everything, or add a fixed high-CRI D65 strip for colour-critical work","Product","Probe 07 results (A, B, C, E, F, I)","P0b-T04","Decision written into BUILD_PLAN D0b",0.25,0.5,R,"To do",NEW)
t("P0b-T10","0b","Your task: read the light bar's model label (Q20)","Hardware","The bar, its puck, the box","—","Model in SPEC Q20",0.25,0.5,R,"To do",BP)
t("P0b-T11","0b","Light bar vs sensor (Q21): lux bar off / 30 % / 100 %, three readings each","Hardware","Fixed room light, `bin/light status`","P0b-T10, P0-T12","Q21 answered with deltas and target changes",0.5,1,R,"To do",BP)
t("P0b-T12","0b","Shell light-bar prompt: ask logic in lightd + SwiftBar item (Turn on / Not tonight)","Frontend (shell UI) / Backend","SwiftBar, lightd state files","P0-T08, P0b-T10","A week: ≤ 1 prompt an evening; withdrawn at > 20 lx; nothing sent without a tap",2,4,R,"To do",BP)
t("PM-09","0b","D-LB: Xiaomi integration yes or no, by model","Product","Q20, Q21; a `miiocli` status try for a 1S","P0b-T10, P0b-T11","Decision written into BUILD_PLAN D-LB",0.25,0.5,R,"To do",NEW)

# ── Design (start during Phase 0, needed by Phase 1)
t("DS-01","1","Popover wireframe: layout, hierarchy, override as the first control (R06 §3)","Design","Figma, R06 §3, DESIGN_TOKENS.md","PM-04","Wireframe approved by you; every FR with UI has a place",2,4,R,"To do",NEW)
t("DS-02","1","State designs: Adaptive, Colour-critical, Override incomplete, Sensor offline, DDC blocked, Display asleep, Cap reached","Design","R06 states table + the new 'NOT neutral' state from the review","DS-01","7 states, each distinguishable without colour (text + shape)",2,4,R,"To do",NEW)
t("DS-03","1","Menu bar icon set (adaptive tint, critical, warning); tint feasibility spike","Design / Frontend","SF Symbols app, a 30-min Xcode spike","DS-01, P1-T01","Icons at 1x/2x in light and dark; decision on tint vs shape-only",1,3,NR,"To do",NEW)
t("DS-04","1","Map DESIGN_TOKENS.md to SwiftUI (colour, type, radius, springs)","Design","DESIGN_TOKENS.md §9","DS-01","Token table with SwiftUI names, ready for P1-T02",1,3,R,"To do",NEW)
t("DS-05","1","Microcopy for states, errors and the override failure reasons","Design (content)","The prototype's messages (`gain_rc_reason`)","DS-02","All strings in one file; each error says what to do",1,2,R,"To do",NEW)

# ── Phase 1: native menu bar companion (shell still drives hardware)
t("P1-T01","1","Xcode project: SwiftUI app, LSUIElement, macOS 14 target","DevOps","Xcode, Apple ID","PM-04 (D0)","Builds and runs with no Dock icon",2,6,NR,"To do",BP)
t("P1-T08","1","Stable code-signing identity (not 'Sign to Run Locally')","DevOps","Free Apple ID personal team","P1-T01","Local Network grant survives two rebuilds",0.5,2,NR,"To do",BP)
t("P1-T02","1","MenuBarExtra(.window) with the designed layout","Frontend","SwiftUI","P1-T01, DS-01, DS-04","Popover opens from the menu bar, matches the wireframe",2,5,R,"To do",BP)
t("P1-T03","1","State reader: ~/.lighting/state/* into an @Observable model","Backend","Swift, Observation","P1-T02","Mode, Kelvin, lux, counts match `bin/light status`",3,8,R,"To do",BP)
t("P1-T04","1","Override button runs `bin/light critical toggle`; shows 'NOT neutral' on exit 1","Backend / Frontend","Foundation Process","P1-T03","Toggle works; failure reason shown (FR-30)",2,5,NR,"To do",BP)
t("P1-T05","1","Nudge buttons run `bin/light brighter/dimmer`","Frontend","SwiftUI","P1-T04","±5 applied; offset shown",1,3,R,"To do",BP)
t("P1-T06","1","All status states and the icon","Frontend","DS-02, DS-03, DS-05","P1-T03, DS-02, DS-03, DS-05","Each state appears when its state file says so",3,8,R,"To do",BP)
t("P1-T07","1","Launch at login (SMAppService.mainApp)","DevOps","ServiceManagement","P1-T01","Survives a reboot",1,3,NR,"To do",BP)
t("DS-06","1","Accessibility pass: contrast over the blur (light + dark), VoiceOver labels","Design / QA","Accessibility Inspector","P1-T06","Contrast measured; every control has a label",1,2,R,"To do",NEW)
t("QA-01","1","Phase 1 check: override latency (NFR-01), states, reboot","QA","TEST_PLAN M-08, M-09","P1-T06, P1-T07","Pass/fail recorded",1,2,R,"To do",NEW)
t("PM-05","1","D1: is Swift workable for you? Continue or stop at the companion","Product","Hours actually spent in P1","QA-01","Decision recorded",0.25,0.5,R,"To do",NEW)

# ── Phase 2: engine in Swift
t("P2-T01","2","Swift package Engine with a test target","Backend","Swift Package Manager","P1-T01","`swift test` runs",1,3,R,"To do",BP)
t("P2-T06","2","Parity fixtures: engine.awk → JSON","Backend / QA","awk, a small script","P2-T01","Fixtures for filter, curve, Kelvin, gains committed",2,4,R,"To do",BP)
t("P2-T02","2","Port the lux filter (FR-03)","Backend","Swift","P2-T06","Parity within 1e-4 (U-F*)",2,4,R,"To do",BP)
t("P2-T03","2","Port the brightness curve (FR-10)","Backend","Swift","P2-T06","U-B* pass, incl. malformed points",2,4,R,"To do",BP)
t("P2-T04","2","Port Kelvin + gains, floor and neutral clamp (FR-20/21)","Backend","Swift, colour maths (R03)","P2-T01","U-K*, U-G*, U-C* pass",3,6,R,"To do",BP)
t("P2-T05","2","Android-style nudge (FR-11)","Backend","Android BrightnessMappingStrategy (R01)","P2-T03","U-N* pass",4,10,NR,"To do",BP)

# ── Phase 3: native sensor client
t("P3-T01","3","LuxClient: SSE over URLSession.bytes, filter by ID (FR-01, FR-04)","Backend","Swift concurrency","P2-T02","Correct values from test/fake_sensor.py; bad samples dropped",3,8,NR,"To do",BP)
t("P3-T02","3","Reconnect/backoff + stale state (FR-02)","Backend","Swift","P3-T01","'Offline' within STALE_SECS, then recovers",2,5,R,"To do",BP)
t("P3-T03","3","Local Network permission: NSLocalNetworkUsageDescription + waitsForConnectivity","Backend / DevOps","Info.plist, TN3179","P3-T01, P1-T08","Prompt on first run; still allowed after reboot",1,4,NR,"To do",BP)
t("P3-T04","3","Show the app's lux next to lightd's; compare for 1 h","QA","Both running","P3-T02","Agree within sensor noise",1,2,R,"To do",BP)

# ── Phase 4: DDC in Swift (the hard one)
t("P4-T01","4","Bridging header for IOAVService (R02 §1.1)","Backend","Obj-C bridging, private API","P1-T01","Compiles and links",1,3,NR,"To do",BP)
t("P4-T02","4","IORegistry walk: find the AOC, pick 0x37/0xB7 (FR-43)","Backend","IOKit; port of m1ddc ioregistry.m","P4-T01, P0-T02","Exactly one external service; address matches m1ddc",6,16,GH,"To do",BP)
t("P4-T03","4","DDC packets: write/read with checksum; write count from Q1","Backend","I2C/DDC-CI, the AOC","P4-T02","`set blue 40` lands; read-back matches if Q2 allows",4,10,GH,"To do",BP)
t("P4-T04","4","DDCWriter actor: scheduler, caps, reserve, user-write spacing, write log (FR-41/42/44)","Backend","Swift actors","P4-T03","I-D* pass against a mock transport",5,12,NR,"To do",BP)
t("P4-T05","4","Single-writer handover (FR-40)","Backend","pgrep equivalent (NSRunningApplication)","P4-T04","M-11: never two writers",2,4,R,"To do",BP)
t("P4-T06","4","App drives white point + override; lightd stopped","Backend","All of the above","P4-T05, P3-T02, P3-T03","US-2, US-3 met on hardware",3,8,NR,"To do",BP)
t("P4-T07","4","Neutral on quit and crash recovery (FR-45)","Backend","","P4-T04","kill -9 → neutral after next launch",1,3,R,"To do",BP)
t("P4-T08","4","Adaptive brightness in the app (FR-10, FR-12)","Backend","Ported filter + curve","P4-T06, P2-T02, P2-T03","US-1 met on hardware",2,5,R,"To do",BP)
t("P4-T09","4","'Warm now' presets (FR-22)","Frontend / Backend","SwiftUI menu","P4-T06","Applies in 2 s; cleared on next recompute",1,2,R,"To do",BP)
t("QA-02","4","Hardware validation: M-08 override under changing light, M-09 restart, M-11 other app, M-12 kill -9","QA","TEST_PLAN §4","P4-T07, P4-T08","All pass; write counts recorded",2,4,R,"To do",NEW)
t("PM-06","4","D4: if P4-T02/T03 failed after ~20 h, stop and keep the shell for DDC","Product","Hours log","P4-T03","Decision recorded",0.25,0.5,R,"To do",NEW)

# ── Phase 5: system events
t("P5-T01","5","Sleep/wake and display sleep: gate + reapply once (FR-50/51)","Backend","NSWorkspace notifications","P4-T04","M-01–M-03 pass",3,6,NR,"To do",BP)
t("P5-T02","5","Display reconfiguration → rediscover (FR-52)","Backend","CoreGraphics C callback","P4-T02","M-04 passes",3,8,GH,"To do",BP)
t("P5-T03","5","Fault counters: stop a VCP after 20 consecutive faults (NFR-05)","Backend","","P4-T04","I-D07 passes",1,3,R,"To do",BP)
t("QA-03","5","Manual QA M-01 to M-07 across a week","QA","TEST_PLAN §4","P5-T01, P5-T02","All pass",2,3,R,"To do",NEW)

# ── Phase 6: shell retired
t("P6-T02","6","Native Android-style nudges + UI (FR-11)","Frontend / Backend","P2-T05 engine","P4-T08, P2-T05, P5-T01, P5-T02","US-4 met",2,4,R,"To do",BP)
t("P6-T03","6","Import config.sh (FR-70); retire lightd","Backend / DevOps","launchctl","P4-T08","Fresh install reproduces the shell's behaviour",2,5,R,"To do",BP)
t("QA-04","6","One-week soak of the native app","QA","TEST_PLAN §5","P6-T03","Soak criteria pass",1.75,1.75,R,"To do",NEW)
t("PM-07","6","D6 retrospective: done; decide on Phases 7–8","Product","Soak log","QA-04","Decision recorded",0.5,1,R,"To do",NEW)

# ── Phase 7 (optional): settings
t("DS-07","7","Settings screen design: curve table, gain table, limits","Design","Figma","PM-07","Approved design",2,4,R,"Optional",NEW)
t("P7-T01","7","Settings scene","Frontend","SwiftUI Settings","P6-T03, DS-07","Edits persist and apply",6,14,R,"Optional",BP)
t("DS-08","7","Curve chart design (only with a week of data)","Design","Lux log","P7-T01","Approved design",1,3,R,"Optional",NEW)
t("P7-T02","7","Curve chart (Swift Charts)","Frontend","Swift Charts","P7-T01, DS-08","Curve + today's lux trace",4,10,R,"Optional",BP)

# ── Phase 8: bias light and desk light bar in the app (after Phase 5). P8-T01 moved to P0b-T04 (2026-10-11)
t("DS-09","8","Design: bias status row (6 states) and the light-bar prompt (notification + popover row)","Design","R06 §3.1–3.2","DS-02","States approved; each distinguishable without colour",1,2,R,"To do",NEW)
t("P8-T02","8","NWConnection UDP sender, multicast group + unicast scan, manual IPs, source-address fallback (FR-60)","Backend","Network framework","P3-T03, P0b-T04","Both lights found; commands land; I-G* pass",4,10,NR,"To do",BP)
t("P8-T03","8","BiasController: level from BIAS_CAL, follow K, 6500 K override, off states incl. willSleep, rate limits, reachability (FR-61–67)","Backend","NSWorkspace notifications","P8-T02, P4-T06, P5-T01","US-7 AC1–AC5 on hardware",3,7,NR,"To do",BP)
t("P8-T04","8","Bias status row and states","Frontend","SwiftUI","P8-T03, P1-T06, DS-09","Each state shown when triggered",1,3,R,"To do",BP)
t("P8-T05","8","Light-bar prompt: UNUserNotificationCenter actionable notification + popover row (FR-80–83, 85, 87)","Frontend / Backend","UserNotifications","P3-T02, P1-T06, P0b-T12, DS-09","US-8 AC1–AC4 over a week; works with notifications denied",3,6,NR,"To do",BP)
t("P8-T06","8","Light-bar control: Yeelight LAN (2–4 h) or miIO with a token (6–12 h) (FR-84, FR-86)","Backend","The model from Q20; Keychain","PM-09 (yes), P8-T05","One tap sends one command; failure shown",2,12,GH,"Only if the bar is controllable",BP)
t("QA-05","8","Hardware check: US-7 and US-8 acceptance criteria with the app","QA","TEST_PLAN; the bars and the light bar","P8-T04, P8-T05","All ACs pass; results recorded",1,2,R,"To do",NEW)

# ── Ongoing
t("DV-01","ongoing","Optional CI: run test/run_tests.sh (and later `swift test`) on every push","DevOps","GitHub Actions","—","Green check on the branch",1,3,R,"Optional",NEW)

FIELDS = ["id","phase","task","type","requires","depends_on","done_when","hours_low","hours_high","difficulty","status","source"]
with open(OUT / "tasks.csv", "w", newline="") as f:
    w = csv.writer(f); w.writerow(FIELDS)
    for r in T: w.writerow(r)

def primary(ty): return ty.split("/")[0].split("(")[0].strip()
def fmt(x): return f"{x:g}"

PHASES = {
 "0":"Phase 0: calibrate and live with the shell system (now)",
 "0b":"Phase 0b: bias light and desk light bar in the shell (now)",
 "1":"Phase 1: native menu bar companion (shell still drives the hardware)",
 "2":"Phase 2: the engine in Swift",
 "3":"Phase 3: native sensor client",
 "4":"Phase 4: DDC in Swift (the hard one)",
 "5":"Phase 5: sleep, wake and replugging",
 "6":"Phase 6: shell retired",
 "7":"Phase 7 (optional): settings and chart",
 "8":"Phase 8: bias light and desk light bar in the app (after Phase 5)",
 "ongoing":"Ongoing (optional)",
}
optional = lambda r: r[10] in ("Optional", "Only if P0-T06 fails", "Only if the bar is controllable")

# Totals by type, core (non-optional) vs optional
by = collections.OrderedDict()
for r in T:
    k = primary(r[3]); d = by.setdefault(k, [0, 0, 0, 0, 0])
    if optional(r): d[3] += r[7]; d[4] += r[8]
    else: d[0] += 1; d[1] += r[7]; d[2] += r[8]
CORE = ("1","2","3","4","5","6")
new_lo = sum(r[7] for r in T if r[11] == NEW and not optional(r) and r[1] in CORE)
new_hi = sum(r[8] for r in T if r[11] == NEW and not optional(r) and r[1] in CORE)
core = [r for r in T if not optional(r) and r[1] in CORE]
core_lo = sum(r[7] for r in core); core_hi = sum(r[8] for r in core)
def span(ph):
    rows = [r for r in T if r[1] == ph and not optional(r)]
    return sum(r[7] for r in rows), sum(r[8] for r in rows)
p0b_lo, p0b_hi = span("0b"); p8_lo, p8_hi = span("8")

L = []
L.append("# Task board\n")
L.append("Status: 2026-09-27; bias light and desk light bar added 2026-10-11 (Phase 0b, Phase 8). Generated from BUILD_PLAN, SPEC, TEST_PLAN, RESEARCH_06 and RESEARCH_08. The same tasks are in [`tasks.csv`](tasks.csv), for import into Notion, Linear, Jira or GitHub Projects.\n")
L.append("## How to read it\n")
L.append("**Type** is the kind of work, as on a product team. In a native Mac app the split is:\n")
L.append("| Type | Here, that means |\n|---|---|")
L.append("| **Product** | Decisions, scope, schedule, closing open questions. Mostly short, but they gate everything |")
L.append("| **Design** | UX, layout, states, icons, tokens, microcopy, accessibility (Figma, SF Symbols) |")
L.append("| **Frontend** | SwiftUI views: the popover, buttons, states, settings. Plus the shell's SwiftBar/Shortcut UI in Phase 0 |")
L.append("| **Backend** | The app's core, with no UI: engine maths, sensor client, DDC transport, scheduler, system events, config. There's no server; \"backend\" here is the code behind the views |")
L.append("| **Hardware** | Probes on the real Mac, monitor and sensor; ESP32 firmware |")
L.append("| **DevOps** | Xcode project, signing, launch at login, launchd, CI |")
L.append("| **QA** | Manual checks and soak weeks on real hardware (automated tests live inside each Backend task's \"done when\") |\n")
L.append("A type like \"Backend / Frontend\" means both; the first one is the main kind of work.\n")
L.append("- **Source:** `BUILD_PLAN` tasks keep their IDs and hours. Tasks marked **new** (DS-, PM-, QA-, DV-, P0-T03b, P0-T12, P0-T13; added 2026-10-11: PM-08, PM-09, DS-09, QA-05) weren't in BUILD_PLAN. The docs implied them: R06's design spec, SPEC's open decisions, TEST_PLAN's manual checks. Their hours are my estimates, on the same basis as BUILD_PLAN's.")
L.append("- **Hours** are ranges for you learning Swift with AI pair-programming (BUILD_PLAN, \"How to read the estimates\").")
L.append("- **Everyone is you.** One person holds every role, so the types are for planning your weeks (a design day, a hardware evening), not for handing work to other people.\n")

def state(st):
    if st.startswith("Done"): return "done"
    if st.startswith("In progress"): return "in progress"
    if st.startswith("Not needed"): return "not needed"
    if st.startswith("Run;"): return "in progress"
    if st.startswith("Optional") or st.startswith("Only if"): return "optional"
    return "to do"
MARKS = {"done": "✅ ", "in progress": "🔄 ", "not needed": "➖ ", "optional": "", "to do": ""}
def mark(st): return MARKS[state(st)]

L.append("## Progress\n")
L.append("✅ done · 🔄 in progress · ➖ not needed. Everything else is to do or optional.\n")
cnt = collections.Counter(state(r[10]) for r in T)
L.append("| Done | In progress | Not needed | To do | Optional |\n|---|---|---|---|---|")
L.append(f"| {cnt['done']} | {cnt['in progress']} | {cnt['not needed']} | {cnt['to do']} | {cnt['optional']} |\n")
L.append("**Finished so far:**")
for r in T:
    if state(r[10]) == "done": L.append(f"- ✅ **{r[0]}** {r[2]}: {r[10][5:] if r[10].startswith('Done ') else r[10]}")
L.append("\n**In progress:**")
for r in T:
    if state(r[10]) == "in progress": L.append(f"- 🔄 **{r[0]}** {r[2]}: {r[10]}")
L.append("")
L.append("Also done, outside these tasks:")
L.append("- the shell prototype, the probe kit and the 127-check test suite;")
L.append("- two review rounds (REVIEW_2026-09-26.md);")
L.append("- RESEARCH_01–08, SPEC, BUILD_PLAN and TEST_PLAN;")
L.append("- the first live hardware run and its fixes;")
L.append("- `bin/light update`.")
L.append("All of it is in `docs/lighting-app/` and `lighting-prototype/`.\n")

L.append("## Summary\n")
L.append("| Type | Core tasks (Phases 0, 0b, 1–6, 8) | Core hours | Optional hours |\n|---|---|---|---|")
for k, (n, lo, hi, olo, ohi) in by.items():
    L.append(f"| {k} | {n} | {fmt(lo)}–{fmt(hi)} | {fmt(olo)}–{fmt(ohi)} |" if (olo or ohi) else f"| {k} | {n} | {fmt(lo)}–{fmt(hi)} | — |")
tot = [sum(v[i] for v in by.values()) for i in range(5)]
L.append(f"| **All** | **{tot[0]}** | **{fmt(tot[1])}–{fmt(tot[2])}** | {fmt(tot[3])}–{fmt(tot[4])} |\n")
L.append(f"- **Phases 1–6 (the native app):** about {round(core_lo)}–{round(core_hi)} h. BUILD_PLAN's tasks alone are 72–179 h; the extra {round(new_lo)}–{round(new_hi)} h is the design, QA and decision work that BUILD_PLAN left implicit.")
L.append(f"- **Phase 0b (bias light + light bar, shell, now):** {fmt(p0b_lo)}–{fmt(p0b_hi)} h, run alongside Phase 0's soak. **Phase 8 (the same in the app):** {fmt(p8_lo)}–{fmt(p8_hi)} h, plus 2–12 h for P8-T06 if the light bar can be controlled (D-LB).")
L.append("- **Backend is most of the work, and nearly all the risk:** the three \"genuinely hard\" app tasks (P4-T02, P4-T03, P5-T02) are all Backend.")
L.append("- **Design is small but comes first:** Phase 1's views depend on DS-01 to DS-05, so they should be done before or alongside P1-T01.\n")

L.append("## Critical path\n")
L.append("The longest chain of tasks that depend on each other. A delay here delays everything:\n")
L.append("P0-T01 → P0-T03 → P0-T03b → P0-T05 → P0-T06 → P0-T08 → P0-T11 (soak) → **PM-04 (D0)** → P1-T01 → **P4-T01 → P4-T02 → P4-T03** → P4-T04 → P4-T05 → P4-T06 → P4-T08 → P6-T03 → QA-04 → PM-07\n")
L.append("That's 36–86 h of hands-on work end to end (computed from the dependencies), plus the soak weeks.\n")
L.append("**What this means for the order of work:**")
L.append("- **The DDC work (P4-T01 to T03) needs only the Xcode project and the Q9 answer**, not the engine or the sensor client. It's also the biggest risk: all three \"genuinely hard\" app tasks are there, and D4 says stop if it fails after ~20 h.")
L.append("- **Recommendation:** run P4-T01 to P4-T03 as a time-boxed spike right after P1-T01, before Phases 2–3. If the AOC can't be driven from your own code, you find out after ~10–30 h instead of after ~60–150. Phases 2–3 are routine and can follow, or run between spike sessions.")
L.append("- **Design (DS-01 to DS-05) runs during the soak weeks**, so it doesn't extend the path, as long as it's done by P1-T02.\n")

L.append("## The board\n")
for ph, title in PHASES.items():
    rows = [r for r in T if r[1] == ph]
    if not rows: continue
    L.append(f"### {title}\n")
    L.append("| ID | Task | Type | Requires | Depends on | Done when | Hours | Difficulty | Status |")
    L.append("|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        tag = " *(new)*" if r[11] == NEW else ""
        hrs = fmt(r[7]) if r[7] == r[8] else f"{fmt(r[7])}–{fmt(r[8])}"
        L.append(f"| {r[0]}{tag} | {r[2]} | {r[3]} | {r[4] or '—'} | {r[5]} | {r[6]} | {hrs} | {r[9]} | {mark(r[10])}{r[10]} |")
    L.append("")

L.append("## Not on the board\n")
L.append("These are deliberately excluded (SPEC §3 and \"What not to build\"): multiple monitors, Intel, the App Store, permanent learning, spline curves, smooth DDC transitions, contrast or HDR, screen-colour sync for the bias light, and the Govee cloud API. Also no automatic light-bar switching, and no Govee BLE or Matter path. Settings UI waits for Phase 7. (Changed 2026-10-11: \"Govee waits for a strip\" is gone; the bars are bought.)\n")
L.append("## Assumptions\n")
L.append("| Assumption | If wrong |\n|---|---|")
L.append("| You'll do every role yourself | With a second person, Design and Hardware can run in parallel with Backend, and the calendar time shrinks, though the hours don't |")
L.append("| The new tasks' hours are estimates on BUILD_PLAN's basis, not measurements | Recalibrate after Phase 1 with your real hours (PM-05) |")
L.append("| Probe 05's results hold after re-analysis (P0-T03b) | If they don't, P0-T03 goes back to \"To do\", and a colorimeter may enter the D0 decision |")
(OUT / "TASK_BOARD.md").write_text("\n".join(L) + "\n")
print(f"{len(T)} tasks; core by type:", {k: (v[0], v[1], v[2]) for k, v in by.items()}, "phases1-6:", core_lo, core_hi, "new:", new_lo, new_hi)
