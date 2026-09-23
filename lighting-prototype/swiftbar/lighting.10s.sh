#!/bin/bash
# <swiftbar.title>Lighting</swiftbar.title>
# <swiftbar.desc>Adaptive white point / bias light status and colour-critical override</swiftbar.desc>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
#
# SwiftBar (https://github.com/swiftbar/SwiftBar, MIT) runs this every 10 s and renders the
# output as a menu bar item. Install: brew install --cask swiftbar, set its plugin folder,
# then symlink this file into it:  ln -s "$PWD/lighting.10s.sh" ~/SwiftBarPlugins/

PROTO="$(cd "$(dirname "$(readlink "$0" || echo "$0")")/.." && pwd)"
S="${LIGHT_HOME:-$HOME/.lighting}/state"
mode="$(cat "$S/mode" 2>/dev/null || echo adaptive)"
k="$(cat "$S/kelvin" 2>/dev/null || echo '?')"
lux="$(cat "$S/lux" 2>/dev/null || echo '?')"
day="$(date +%Y-%m-%d)"

if [ "$mode" = critical ]; then
    echo "◉ 6500K | sfimage=circle.lefthalf.filled color=#8E8E93"
else
    echo "☀︎ ${k}K | sfimage=sun.max"
fi
echo "---"
echo "Lux: $lux · target: $(cat "$S/target" 2>/dev/null | sed 's/ mode=.*//')"
if [ "$mode" = critical ]; then
    echo "Colour-critical: ON (neutral 6500K) | color=#34C759"
    echo "Turn off → adaptive | bash=$PROTO/bin/light param1=critical param2=off terminal=false refresh=true"
else
    echo "Colour-critical: off"
    echo "Turn ON (freeze at 6500K) | bash=$PROTO/bin/light param1=critical param2=on terminal=false refresh=true"
fi
echo "---"
echo "Warm now (until the room changes)"
for kk in 6000 5500 5000 4500; do
    echo "--${kk}K | bash=$PROTO/bin/light param1=kelvin param2=$kk terminal=false refresh=true"
done
echo "Neutral once | bash=$PROTO/bin/light param1=neutral terminal=false refresh=true"
echo "---"
printf 'DDC writes today: '
for c in brightness red green blue; do printf '%s %s  ' "$c" "$(cat "$S/count_${day}_$c" 2>/dev/null || echo 0)"; done
echo
if launchctl print "gui/$(id -u)/com.lighting.lightd" >/dev/null 2>&1; then echo "lightd: running"; else echo "lightd: NOT running | color=red"; fi
echo "Open write log | bash=/usr/bin/open param1=-e param2=${LIGHT_HOME:-$HOME/.lighting}/writes.log terminal=false"
