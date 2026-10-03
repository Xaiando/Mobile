#!/usr/bin/env bash
# Checks that the app survives what Android does to apps: a first launch
# killed part-way through, being sent Home and brought back, a rotation, a
# memory trim, and being killed while in the background. CI only: it wipes the
# app's data, so use an emulator, never a phone with data on it.
#
#   tool/android/resilience.sh [options] APK OUTPUT_DIR
#
#   --no-install            the app is already installed
#   --interrupt-after SECS  how long the first launch runs before it is killed
#                           (default 30, while the curriculum is installing)
#   --timeout SECONDS       how long a first launch may take to show its first
#                           screen (default 600)
#   --ready TEXT            text on screen that shows the app has started
#                           (default: the onboarding line on a fresh install)
#   --short-timeout SECS    how long the app may take to show its first screen
#                           when it only had a rest (default 60)
#
# The first launch installs the whole curriculum in one transaction, so a kill
# in the middle must leave nothing half done: the next launch starts that work
# again and reaches the first screen. Android kills backgrounded apps whenever
# it likes, and a learner meets this on a slow phone whose first launch takes a
# minute or more.
#
# Writes OUTPUT_DIR/resilience.md (and screenshots, logcat.txt). It never taps.
# Exit status: 0 when every check held, 1 otherwise.
set -u

install=1
interrupt_after=30
limit=600
short=60
ready='I am of legal drinking age'
while [[ ${1:-} == --* ]]; do
  case $1 in
    --no-install) install=0; shift ;;
    --interrupt-after) interrupt_after=${2:?--interrupt-after needs seconds}; shift 2 ;;
    --timeout) limit=${2:?--timeout needs a number}; shift 2 ;;
    --ready) ready=${2:?--ready needs text}; shift 2 ;;
    --short-timeout) short=${2:?--short-timeout needs a number}; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
apk=${1:?usage: $0 [options] APK OUTPUT_DIR}
out=${2:?usage: $0 [options] APK OUTPUT_DIR}
package=com.xaiando.sommelier
activity=$package/.MainActivity
mkdir -p "$out"
status=0
recovered=0
report=$out/resilience.md

now_ms() { date +%s%3N; }
# The pauses give Android time to act; the tests of this script shrink them.
pause() { sleep "$(awk -v s="$1" -v k="${RESILIENCE_PAUSE_FACTOR:-1}" 'BEGIN { print s * k }')"; }
note() { echo "$*" | tee -a "$report"; }
fail() { note "- **FAIL** $*"; status=1; }
adbq() { timeout 60 adb "$@" 2>&1 | tr -d '\r'; }
running() { [[ -n $(adbq shell pidof "$package") ]]; }

# True when the screen shows TEXT. Reading the screen starts a Java process on
# the device, so callers read it sparingly.
screen_has() {
  local xml
  xml=$(timeout 60 adb exec-out uiautomator dump /dev/tty 2>/dev/null | tr -d '\000\r')
  [[ $xml == *"$1"* ]]
}

# Waits for TEXT on screen, backing off 2, 4, 8, 16 then 20 seconds between
# looks. Prints the seconds waited; returns 1 on a timeout, 2 if the app died.
wait_for_text() { # TEXT SECONDS
  local text=$1 seconds=$2 begin elapsed delay=2 seen=0
  begin=$(now_ms)
  while :; do
    elapsed=$(( $(now_ms) - begin ))
    if (( elapsed > seconds * 1000 )); then return 1; fi
    if ! running; then
      # A process still being started is not a stopped one: give it a grace.
      if (( seen || elapsed > ${RESILIENCE_START_GRACE:-15} * 1000 )); then return 2; fi
      sleep 2
      continue
    fi
    seen=1
    if screen_has "$text"; then
      awk -v ms=$(( $(now_ms) - begin )) 'BEGIN { printf "%.1f", ms / 1000 }'
      return 0
    fi
    sleep "$delay"
    delay=$(( delay * 2 > 20 ? 20 : delay * 2 ))
  done
}

expect_ready() { # LABEL SECONDS
  local label=$1 seconds=$2 waited code
  waited=$(wait_for_text "$ready" "$seconds")
  code=$?
  case $code in
    0) note "- $label: the first screen was back after $waited s" ;;
    1) fail "$label: no \"$ready\" within $seconds s" ;;
    2) fail "$label: the app stopped running" ;;
  esac
  return $code
}

: > "$report"
note "# Android resilience check"
note ""

if [[ $(adbq get-state) != device ]]; then
  fail "no device is attached"
  exit 1
fi
if (( install )); then
  result=$(adbq install -r -t "$apk")
  if [[ $result != *Success* ]]; then
    fail "install failed: $result"
    exit 1
  fi
fi
if [[ -z $(adbq shell pm path "$package") ]]; then
  fail "$package is not installed"
  exit 1
fi
adbq logcat -c > /dev/null

note "A first launch that the system kills"
note ""
adbq shell pm clear "$package" > /dev/null
pause 2
adbq shell am start -W -n "$activity" > /dev/null
sleep "$interrupt_after"
pid=$(adbq shell pidof "$package")
if [[ -z $pid ]]; then
  fail "interrupted first launch: the app was not running $interrupt_after s into its first launch"
else
  if screen_has "$ready"; then
    note "- the first launch had already finished after $interrupt_after s, so the kill came after it, not during it; use a smaller --interrupt-after to cut it short"
  else
    note "- killed the app $interrupt_after s into its first launch, before its first screen"
  fi
  adbq shell kill -9 "$pid" > /dev/null
  pause 3
  if running; then
    fail "the app was still running after kill -9"
  else
    adbq shell am start -W -n "$activity" > /dev/null
    if expect_ready "relaunch after the kill" "$limit"; then
      recovered=1
      timeout 60 adb exec-out screencap -p > "$out/recovered.png" 2>/dev/null
    fi
  fi
fi
note ""

if (( recovered )); then
  note "What Android does to a running app"
  note ""
  adbq shell input keyevent KEYCODE_HOME > /dev/null
  pause 3
  adbq shell am start -W -n "$activity" > /dev/null
  expect_ready "back from the home screen" "$short"

  adbq shell settings put system accelerometer_rotation 0 > /dev/null
  adbq shell settings put system user_rotation 1 > /dev/null
  pause 4
  if running; then
    timeout 60 adb exec-out screencap -p > "$out/landscape.png" 2>/dev/null
    note "- rotated to landscape: the app kept running (landscape.png)"
  else
    fail "rotated to landscape: the app stopped running"
  fi
  adbq shell settings put system user_rotation 0 > /dev/null
  pause 4
  expect_ready "rotated back to portrait" "$short"
  adbq shell settings put system accelerometer_rotation 1 > /dev/null

  # The system may refuse this on a build that is not debuggable (a phone):
  # say so, and do not count a trim that never happened.
  trim=$(adbq shell am send-trim-memory "$package" RUNNING_CRITICAL)
  pause 3
  if [[ $trim == *Exception* || $trim == *Error* || $trim == *refus* ]]; then
    note "- the system refused the memory trim, so none was applied: $(echo "$trim" | head -1)"
  else
    expect_ready "after a critical memory trim" "$short"
  fi

  adbq shell input keyevent KEYCODE_HOME > /dev/null
  pause 3
  adbq shell am kill "$package" > /dev/null
  pause 3
  if running; then
    note "- the system kept the backgrounded app alive, so no cold start was exercised here"
  else
    note "- the system killed the backgrounded app"
  fi
  adbq shell am start -W -n "$activity" > /dev/null
  expect_ready "back after being killed in the background" $(( short * 2 ))
  note ""
fi

adbq logcat -d > "$out/logcat.txt"
crash='FATAL EXCEPTION|ANR in '"$package"'|Fatal signal|UnsatisfiedLinkError|Process: '"$package"', PID'
note "Crash scan"
note ""
if grep -E -q "$crash" "$out/logcat.txt"; then
  fail "logcat shows a crash, ANR or native-library failure:"
  note '```'
  grep -E -B1 -A6 "$crash" "$out/logcat.txt" | head -60 | tee -a "$report"
  note '```'
else
  note "- no crash, ANR or native-library failure in logcat"
fi
note ""
if (( status )); then note "**Result: FAILED**"; else note "**Result: passed**"; fi
[[ -n ${GITHUB_STEP_SUMMARY:-} ]] && cat "$report" >> "$GITHUB_STEP_SUMMARY"
exit $status
