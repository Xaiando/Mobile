#!/usr/bin/env bash
# Runs the backup round trip (tool/android_tour/roundtrip.dart) on the
# connected emulator: a wine and its photo are saved through the journal
# editor, exported through Settings, Your data, lost, imported back, and a file
# that is not a backup is refused without touching the data.
#
#   tool/android/data_roundtrip.sh OUTPUT_DIR
#
# Only the platform's file dialog is replaced, by memory: everything else is
# the app's own, running on Android. Whether Samsung's file dialogs take the
# export and offer it back for import is for the phone (docs/android-
# acceptance.md, rows G1 to G3). Run it from the repository root, with adb and
# flutter on PATH and one device attached. It wipes the app's data on the
# device before the run: use an emulator.
#
# Writes to OUTPUT_DIR: summary.md, drive.log (the run's own report) and
# flutter-log.txt (what the app printed).
# Exit status: 0 when the round trip held, 1 otherwise.
set -u

out=${1:?usage: $0 OUTPUT_DIR}
rm -f "$out/summary.md" "$out/drive.log" "$out/flutter-log.txt"
mkdir -p "$out"
summary=$out/summary.md
log=$out/flutter-log.txt
status=0
: > "$summary"
: > "$log"
note() { echo "$*" | tee -a "$summary"; }
fail() { note "- **FAIL** $*"; status=1; }

note "# Android backup round trip"
note ""

adb logcat -c > /dev/null 2>&1
adb logcat -v raw -s flutter:I > "$log" 2>/dev/null &
logcat_pid=$!

# Start from nothing: onboarding must not have been finished by an earlier run.
adb shell pm clear com.xaiando.sommelier > /dev/null 2>&1

flutter drive \
  --driver=tool/android_tour/driver.dart \
  --target=tool/android_tour/roundtrip_test.dart \
  --dart-define=SOMMELIER_DATABASE=integration \
  2>&1 | tee "$out/drive.log"
drive_status=${PIPESTATUS[0]}

sleep 3
kill "$logcat_pid" 2>/dev/null
wait "$logcat_pid" 2>/dev/null

if (( drive_status != 0 )); then
  fail "the round trip failed (flutter drive exit status $drive_status); drive.log has the details"
fi
if ! grep -q 'ROUNDTRIP_DONE ' "$log"; then
  fail "the round trip never finished: the app printed no ROUNDTRIP_DONE line"
fi

problems=$(grep -o 'ROUNDTRIP_PROBLEM .*' "$log" | sed 's/^ROUNDTRIP_PROBLEM //')
if [[ -n $problems ]]; then
  status=1
  note "Problems the round trip found:"
  note ""
  echo "$problems" | sed 's/^/- /' | tee -a "$summary"
elif (( status == 0 )); then
  note "The round trip found no problems: the wine and its photo came back from the export, and a file that is not a backup changed nothing."
fi

note ""
if (( status )); then note "**Result: FAILED**"; else note "**Result: passed**"; fi
[[ -n ${GITHUB_STEP_SUMMARY:-} ]] && cat "$summary" >> "$GITHUB_STEP_SUMMARY"
exit $status
