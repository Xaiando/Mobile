#!/usr/bin/env bash
# Runs the screen tour (tool/android_tour) on the connected emulator and turns
# the app's "TOUR_SHOT <name>" lines in logcat into screenshots.
#
#   tool/android/screen_tour.sh [options] OUTPUT_DIR
#
#   --shape SHAPE    put the emulator's display into the shape of another
#                    screen for the whole tour: phone (the default, the
#                    emulator's own screen), fold-cover, fold-open,
#                    fold-open-wide or fold-split, the Galaxy Z Fold 6's
#                    screens (window_shape.sh)
#   --resize-walk    after the walk, open the wine editor, type a producer and
#                    let the app ask this script, with "TOUR_RESIZE <shape>"
#                    lines, to change the display through each Fold shape, as
#                    folding and unfolding does; the typed text must survive
#
# The tour walks every main screen in light, dark and large text. Before each
# shot it prints a TOUR_SHOT line and waits a moment; this script takes a real
# screenshot (the system bars included) as soon as it sees the line. Run it
# from the repository root, with adb and flutter on PATH and one device
# attached. It wipes the app's data on the device before the tour, so that
# every run starts on a fresh database, and it changes the display size when
# asked to: use an emulator.
#
# Writes to OUTPUT_DIR: summary.md, shots/<name>.png, drive.log (the tour's
# own report), flutter-log.txt (what the app printed) and logcat.txt.
# Exit status: 0 when the tour passed and every shot was taken, 1 otherwise.
set -u

shape=phone
resize_walk=0
while [[ ${1:-} == --* ]]; do
  case $1 in
    --shape) shape=${2:?--shape needs a name}; shift 2 ;;
    --resize-walk) resize_walk=1; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
out=${1:?usage: $0 [--shape SHAPE] [--resize-walk] OUTPUT_DIR}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=window_shape.sh
. "$here/window_shape.sh"
if ! shape_known "$shape"; then
  echo "unknown window shape $shape" >&2
  exit 2
fi

# A reused output directory must not carry the last run's pictures into this
# one, or a run that took none would report the old ones as its own.
rm -rf "$out/shots"
rm -f "$out/drive.log" "$out/flutter-log.txt" "$out/logcat.txt" "$out/resize-errors.txt"
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

# The display goes back to its own size however the script ends.
if [[ $shape != phone ]] || (( resize_walk )); then
  trap reset_shape EXIT
fi

adb logcat -c > /dev/null 2>&1

# One process writes what the app prints; another follows that file and
# answers each TOUR_SHOT line with a screenshot, and each TOUR_RESIZE line with
# a change of the display.
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
          *TOUR_RESIZE\ *)
            name=${line##*TOUR_RESIZE }
            set_shape "$name" || echo "$name: $SHAPE_ERROR" >> "$out/resize-errors.txt"
            ;;
        esac
      done <<< "$chunk"
    fi
    sleep 0.4
  done
) &
watcher=$!

# The tour waits for onboarding, which a database left by an earlier run has
# already finished, and Flutter installs over a build with `adb install -r`,
# which keeps its data. Start from nothing.
adb shell pm clear com.xaiando.sommelier > /dev/null 2>&1

if [[ $shape != phone ]]; then
  if set_shape "$shape"; then
    note "- window shape: $shape ($(shape_label "$shape"))"
  else
    fail "window shape $shape: $SHAPE_ERROR"
    kill "$watcher" "$logcat_pid" 2>/dev/null
    wait "$watcher" "$logcat_pid" 2>/dev/null
    note ""
    note "**Result: FAILED**"
    [[ -n ${GITHUB_STEP_SUMMARY:-} ]] && cat "$summary" >> "$GITHUB_STEP_SUMMARY"
    exit 1
  fi
else
  note "- window shape: phone (the emulator's own screen)"
fi

defines=(--dart-define=SOMMELIER_DATABASE=integration)
if (( resize_walk )); then defines+=(--dart-define=TOUR_RESIZE_WALK=true); fi

flutter drive \
  --driver=tool/android_tour/driver.dart \
  --target=tool/android_tour/tour_test.dart \
  "${defines[@]}" \
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
if [[ -s $out/resize-errors.txt ]]; then
  while IFS= read -r line; do fail "the display would not change: $line"; done < "$out/resize-errors.txt"
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

windows=$(grep -o 'TOUR_WINDOW .*' "$log" | sed 's/^TOUR_WINDOW //')
if [[ -n $windows ]]; then
  note ""
  note "The window as the app saw it (logical pixels, and the navigation it chose):"
  note ""
  note '```'
  echo "$windows" | tee -a "$summary"
  note '```'
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
