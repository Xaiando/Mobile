#!/usr/bin/env bash
# Starts the app on the connected Android emulator or phone and reports what a
# learner would meet: how long the first launch takes to reach the first
# screen (the curriculum installs into the database then), how long a second
# launch takes, and whether anything crashed. It never taps or types, so it is
# safe on a phone: you do the age confirmation yourself.
#
#   tool/android/emulator_smoke.sh [options] APK OUTPUT_DIR
#
#   --no-install       the app is already installed; only launch and measure
#   --uninstall-after  remove the app afterwards (CI only: this deletes its data)
#   --timeout SECONDS  how long a launch may take to show the first screen
#                      (default 600)
#   --ready TEXT       text on screen that shows the app has started (default:
#                      the onboarding line on a fresh install)
#
# Writes to OUTPUT_DIR: summary.md, device.txt, package.txt, logcat.txt,
# meminfo.txt and first-launch.png. Needs adb on PATH and one device attached.
# Exit status: 0 when the app launched and nothing crashed, 1 otherwise.
set -u

install=1
uninstall_after=0
limit=600
ready='I am of legal drinking age'
while [[ ${1:-} == --* ]]; do
  case $1 in
    --no-install) install=0; shift ;;
    --uninstall-after) uninstall_after=1; shift ;;
    --timeout) limit=${2:?--timeout needs a number}; shift 2 ;;
    --ready) ready=${2:?--ready needs text}; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
apk=${1:?usage: $0 [options] APK OUTPUT_DIR}
out=${2:?usage: $0 [options] APK OUTPUT_DIR}
package=com.xaiando.sommelier
activity=$package/.MainActivity
mkdir -p "$out"
status=0
summary=$out/summary.md

now_ms() { date +%s%3N; }
note() { echo "$*" | tee -a "$summary"; }
fail() { note "- **FAIL** $*"; status=1; }
adbq() { timeout 60 adb "$@" 2>&1 | tr -d '\r'; }

: > "$summary"
note "# Android smoke test"
note ""

state=$(adbq get-state)
if [[ $state != device ]]; then
  fail "no device is attached (adb get-state: ${state:-nothing})"
  exit 1
fi

{
  echo "model:    $(adbq shell getprop ro.product.model)"
  echo "android:  $(adbq shell getprop ro.build.version.release) (API $(adbq shell getprop ro.build.version.sdk))"
  echo "abi:      $(adbq shell getprop ro.product.cpu.abi)"
  echo "page:     $(adbq shell getconf PAGE_SIZE) bytes"
  echo "build:    $(adbq shell getprop ro.build.fingerprint)"
} > "$out/device.txt"
note "Device"
note ""
note '```'
cat "$out/device.txt" | tee -a "$summary"
note '```'
note ""

if (( install )); then
  result=$(adbq install -r -t "$apk")
  if [[ $result != *Success* ]]; then
    fail "install failed: $result"
    note ""
    note "An APK signed with another key cannot replace an installed build."
    note "Export your data in the app first, then uninstall the old build."
    exit 1
  fi
fi
adbq shell dumpsys package "$package" > "$out/package.txt"

wait_for_text() { # TEXT SECONDS -> prints the milliseconds waited
  local text=$1 seconds=$2 begin xml
  begin=$(now_ms)
  while :; do
    if (( $(now_ms) - begin > seconds * 1000 )); then return 1; fi
    if [[ -z $(adbq shell pidof "$package") ]]; then return 2; fi
    xml=$(timeout 60 adb exec-out uiautomator dump /dev/tty 2>/dev/null | tr -d '\000\r')
    if [[ $xml == *"$text"* ]]; then
      echo $(( $(now_ms) - begin ))
      return 0
    fi
    sleep 2
  done
}

launch() { # LABEL -> measures one launch
  local label=$1 total waited code seconds
  adbq shell am force-stop "$package" > /dev/null
  sleep 2
  adbq shell am start -W -n "$activity" > "$out/am-start-$label.txt"
  total=$(sed -n 's/^TotalTime: *//p' "$out/am-start-$label.txt" | head -1)
  waited=$(wait_for_text "$ready" "$limit")
  code=$?
  case $code in
    0)
      seconds=$(awk -v ms="$waited" 'BEGIN { printf "%.1f", ms / 1000 }')
      note "- $label launch: window drawn after ${total:-?} ms, first screen after $seconds s"
      ;;
    1) fail "$label launch: no \"$ready\" within $limit s" ;;
    2) fail "$label launch: the app stopped running" ;;
  esac
  return $code
}

adbq logcat -c > /dev/null
note "Launches"
note ""
if launch first; then
  timeout 60 adb exec-out screencap -p > "$out/first-launch.png" 2>/dev/null
  adbq shell dumpsys meminfo "$package" > "$out/meminfo.txt"
fi
launch second
note ""

adbq logcat -d > "$out/logcat.txt"
note "Crash scan"
note ""
crash='FATAL EXCEPTION|ANR in '"$package"'|Fatal signal|UnsatisfiedLinkError|Process: '"$package"', PID'
if grep -E -q "$crash" "$out/logcat.txt"; then
  fail "logcat shows a crash, ANR or native-library failure:"
  note '```'
  grep -E -B1 -A6 "$crash" "$out/logcat.txt" | head -60 | tee -a "$summary"
  note '```'
else
  note "- no crash, ANR or native-library failure in logcat"
fi
denied=$(grep -c -E 'EACCES|missing INTERNET permission|Permission denied.*(socket|INTERNET)' "$out/logcat.txt")
note "- network attempts the system refused (expected without INTERNET): $denied"
note ""

if [[ -f $out/meminfo.txt ]]; then
  note "Memory after the first launch"
  note ""
  note '```'
  grep -E 'TOTAL PSS|TOTAL RSS|Native Heap|Dalvik Heap|Graphics' "$out/meminfo.txt" | head -6 | tee -a "$summary"
  note '```'
fi

if (( uninstall_after )); then adbq uninstall "$package" > /dev/null; fi
note ""
if (( status )); then note "**Result: FAILED**"; else note "**Result: passed**"; fi
[[ -n ${GITHUB_STEP_SUMMARY:-} ]] && cat "$summary" >> "$GITHUB_STEP_SUMMARY"
exit $status
