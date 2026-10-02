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
#   --control          CI only, needs --uninstall-after: wipe the app's data and
#                      time one more first launch, looking at the screen only
#                      at a few checkpoints, to show how much the polling of
#                      the first measurement slowed the start
#   --checkpoints "60 120 ..."  the control's checkpoints in seconds
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
control=0
checkpoints='60 120 180 240 300 420'
limit=600
ready='I am of legal drinking age'
while [[ ${1:-} == --* ]]; do
  case $1 in
    --no-install) install=0; shift ;;
    --uninstall-after) uninstall_after=1; shift ;;
    --control) control=1; shift ;;
    --checkpoints) checkpoints=${2:?--checkpoints needs seconds}; shift 2 ;;
    --timeout) limit=${2:?--timeout needs a number}; shift 2 ;;
    --ready) ready=${2:?--ready needs text}; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
if (( control && ! uninstall_after )); then
  echo "--control wipes the app's data: use it only with --uninstall-after, on a disposable device" >&2
  exit 2
fi
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

# Every check starts a Java process on the device to read the screen, which on
# a small emulator is heavy enough to slow the very start being timed. So the
# checks back off: 2 s, 4 s, 8 s, 16 s, then every 20 s.
wait_for_text() { # TEXT SECONDS LABEL -> prints the milliseconds waited
  local text=$1 seconds=$2 label=$3 begin elapsed pid xml delay=2 snapshot=0
  begin=$(now_ms)
  while :; do
    elapsed=$(( $(now_ms) - begin ))
    if (( elapsed > seconds * 1000 )); then return 1; fi
    pid=$(adbq shell pidof "$package")
    if [[ -z $pid ]]; then return 2; fi
    if (( ! snapshot && elapsed > 60000 )); then
      # Who is using the CPU while the app is still starting?
      snapshot=1
      adbq shell dumpsys cpuinfo > "$out/cpuinfo-$label.txt"
    fi
    xml=$(timeout 60 adb exec-out uiautomator dump /dev/tty 2>/dev/null | tr -d '\000\r')
    if [[ $xml == *"$text"* ]]; then
      elapsed=$(( $(now_ms) - begin ))
      # utime + stime, in clock ticks (100 a second), of the app so far.
      adbq shell cat "/proc/$pid/stat" | awk '{ print $14 + $15 }' > "$out/ticks-$label.txt"
      # The most memory the app has ever held resident, in kB (the kernel keeps
      # the high-water mark, so no sampling is needed).
      adbq shell cat "/proc/$pid/status" | awk '/^VmHWM:/ { print $2 }' > "$out/peak-$label.txt"
      echo "$elapsed"
      return 0
    fi
    sleep "$delay"
    delay=$(( delay * 2 > 20 ? 20 : delay * 2 ))
  done
}

launch() { # LABEL -> measures one launch
  local label=$1 total waited code seconds cpu peak
  adbq shell am force-stop "$package" > /dev/null
  sleep 2
  adbq shell am start -W -n "$activity" > "$out/am-start-$label.txt"
  total=$(sed -n 's/^TotalTime: *//p' "$out/am-start-$label.txt" | head -1)
  waited=$(wait_for_text "$ready" "$limit" "$label")
  code=$?
  case $code in
    0)
      seconds=$(awk -v ms="$waited" 'BEGIN { printf "%.1f", ms / 1000 }')
      cpu=$(awk '{ printf "%.1f", $1 / 100 }' "$out/ticks-$label.txt" 2>/dev/null)
      peak=$(awk '{ printf "%.0f", $1 / 1024 }' "$out/peak-$label.txt" 2>/dev/null)
      note "- $label launch: window drawn after ${total:-?} ms, first screen after $seconds s; the app used ${cpu:-?} s of CPU and held at most ${peak:-?} MB in memory"
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

control_launch() { # a first launch measured without disturbing it
  local begin at xml seen=none
  adbq shell pm clear "$package" > /dev/null
  sleep 2
  adbq shell am start -W -n "$activity" > /dev/null
  begin=$(now_ms)
  for at in $checkpoints; do
    while (( $(now_ms) - begin < at * 1000 )); do sleep 1; done
    xml=$(timeout 60 adb exec-out uiautomator dump /dev/tty 2>/dev/null | tr -d '\000\r')
    if [[ $xml == *"$ready"* ]]; then seen=$at; break; fi
  done
  if [[ $seen == none ]]; then
    note "- control (data wiped, checked only at $checkpoints s): first screen **not** seen by the last checkpoint"
  else
    note "- control (data wiped, checked only at $checkpoints s): first screen seen by $seen s"
  fi
}
(( control )) && control_launch
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
