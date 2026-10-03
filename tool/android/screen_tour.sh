#!/usr/bin/env bash
# Runs the screen tour (tool/android_tour) on the connected emulator and turns
# the app's "TOUR_SHOT <name>" lines in logcat into screenshots.
#
#   tool/android/screen_tour.sh OUTPUT_DIR
#
# The tour walks every main screen in light, dark and large text. Before each
# shot it prints a TOUR_SHOT line and waits a moment; this script takes a real
# screenshot (the system bars included) as soon as it sees the line. Run it
# from the repository root, with adb and flutter on PATH and one device
# attached. It starts the app on a fresh database, so use an emulator.
#
# Writes to OUTPUT_DIR: summary.md, shots/<name>.png, drive.log (the tour's
# own report), flutter-log.txt (what the app printed) and logcat.txt.
# Exit status: 0 when the tour passed and every shot was taken, 1 otherwise.
set -u

out=${1:?usage: $0 OUTPUT_DIR}
mkdir -p "$out/shots"
summary=$out/summary.md
log=$out/flutter-log.txt
status=0
: > "$summary"
: > "$log"
note() { echo "$*" | tee -a "$summary"; }
fail() { note "- **FAIL** $*"; status=1; }

note "# Android screen tour"
note ""

adb logcat -c > /dev/null 2>&1

# One process writes what the app prints; another follows that file and
# answers each TOUR_SHOT line with a screenshot.
adb logcat -v raw -s flutter:I > "$log" 2>/dev/null &
logcat_pid=$!
(
  seen=0
  while :; do
    size=$(stat -c %s "$log" 2>/dev/null || echo 0)
    if (( size > seen )); then
      chunk=$(tail -c +$(( seen + 1 )) "$log" | head -c $(( size - seen )))
      seen=$size
      while IFS= read -r line; do
        line=${line%$'\r'}
        case $line in
          *TOUR_SHOT\ *)
            name=${line##*TOUR_SHOT }
            name=${name//[^A-Za-z0-9_.-]/_}
            timeout 30 adb exec-out screencap -p > "$out/shots/$name.png" 2>/dev/null
            ;;
        esac
      done <<< "$chunk"
    fi
    sleep 0.4
  done
) &
watcher=$!

flutter drive \
  --driver=tool/android_tour/driver.dart \
  --target=tool/android_tour/tour_test.dart \
  --dart-define=SOMMELIER_DATABASE=integration \
  2>&1 | tee "$out/drive.log"
drive_status=${PIPESTATUS[0]}

sleep 3
kill "$watcher" "$logcat_pid" 2>/dev/null
wait "$watcher" "$logcat_pid" 2>/dev/null
adb logcat -d > "$out/logcat.txt" 2>/dev/null

asked=$(grep -c 'TOUR_SHOT ' "$log")
taken=$(find "$out/shots" -name '*.png' -size +0c | wc -l | tr -d ' ')
note "- the tour asked for $asked shots and $taken were taken"
if (( drive_status != 0 )); then
  fail "the tour failed (flutter drive exit status $drive_status); drive.log has the details"
fi
if (( taken == 0 )); then
  fail "no screenshot was taken"
elif (( taken < asked )); then
  missing=$(grep -o 'TOUR_SHOT .*' "$log" | sed 's/^TOUR_SHOT //; s/[^A-Za-z0-9_.-]/_/g' | while read -r name; do
    [[ -s $out/shots/$name.png ]] || echo "$name"
  done | tr '\n' ' ')
  fail "shots missing: $missing"
fi

problems=$(grep -o 'TOUR_PROBLEM .*' "$log" | sed 's/^TOUR_PROBLEM //')
note ""
if [[ -n $problems ]]; then
  note "Problems the tour found:"
  note ""
  echo "$problems" | sed 's/^/- /' | tee -a "$summary"
else
  note "The tour found no problems."
fi

timings=$(grep -o 'TOUR_TIME .*' "$log" | sed 's/^TOUR_TIME //')
if [[ -n $timings ]]; then
  note ""
  note "Milliseconds to settle (a debug build on an emulator: compare screens, not phones):"
  note ""
  note '```'
  echo "$timings" | tee -a "$summary"
  note '```'
fi

note ""
if (( status )); then note "**Result: FAILED**"; else note "**Result: passed**"; fi
[[ -n ${GITHUB_STEP_SUMMARY:-} ]] && cat "$summary" >> "$GITHUB_STEP_SUMMARY"
exit $status
