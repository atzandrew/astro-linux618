#!/bin/sh
# ftmenu.sh COUNT PERIOD_S: toggle the Plasma launcher COUNT times via D-Bus
# (= the Alt+F1 shortcut path), PERIOD_S apart; log times to events.txt.
# Run as the desktop user (astro-frametrace without FT_ROOT).
: > /var/tmp/ft/events.txt
i=0
while [ $i -lt $1 ]; do
	python3 -c "import time; print(\"%.6f\" % time.monotonic())" >> /var/tmp/ft/events.txt
	qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu >/dev/null
	sleep $2; i=$((i+1))
done
