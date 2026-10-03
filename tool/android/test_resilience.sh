#!/usr/bin/env bash
# Tests resilience.sh against the fake adb in testdata/:
#
#   bash tool/android/test_resilience.sh
#
# Each case runs the real script, with its pauses shrunk, and checks its exit
# status and report.
set -u
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cp "$here/testdata/fake_adb.sh" "$work/bin/adb"
chmod +x "$work/bin/adb"

failures=0
run_case() { # NAME EXPECTED_STATUS EXPECTED_TEXT... -- ENV... -- SCRIPT_ARGS...
  local name=$1 expected=$2; shift 2
  local texts=() envs=() args=()
  while [[ ${1:-} != -- ]]; do texts+=("$1"); shift; done; shift
  while [[ ${1:-} != -- ]]; do envs+=("$1"); shift; done; shift
  args=("$@")
  local out="$work/out-$name"
  rm -rf "$work/state"; mkdir -p "$work/state"
  env PATH="$work/bin:$PATH" FAKE_ADB_DIR="$work/state" RESILIENCE_PAUSE_FACTOR=0.05 RESILIENCE_START_GRACE=1 \
    "${envs[@]}" \
    bash "$here/resilience.sh" --interrupt-after 0 --timeout 6 --short-timeout 4 "${args[@]}" fake.apk "$out" \
    > "$work/log-$name" 2>&1
  local status=$? ok=1
  [[ $status == "$expected" ]] || { ok=0; echo "  exit status $status, expected $expected"; }
  for text in "${texts[@]}"; do
    grep -q -F -- "$text" "$out/resilience.md" 2>/dev/null || { ok=0; echo "  report lacks: $text"; }
  done
  if (( ok )); then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); sed 's/^/     | /' "$work/log-$name" | head -30; fi
}

run_case success 0 \
  "killed the app 0 s into its first launch, before its first screen" \
  "relaunch after the kill: the first screen was back after" \
  "back from the home screen: the first screen was back after" \
  "rotated to landscape: the app kept running" \
  "rotated back to portrait: the first screen was back after" \
  "after a critical memory trim: the first screen was back after" \
  "the system killed the backgrounded app" \
  "back after being killed in the background: the first screen was back after" \
  "no crash, ANR or native-library failure in logcat" "**Result: passed**" \
  -- FAKE_READY_AFTER_MS=1500 --
[[ -s $work/out-success/recovered.png && -s $work/out-success/landscape.png ]] \
  || { echo "FAIL success: no screenshots"; failures=$((failures + 1)); }

run_case finished_before_the_kill 0 \
  "had already finished after 0 s, so the kill came after it" "**Result: passed**" \
  -- FAKE_READY_AFTER_MS=0 --

run_case not_running_before_the_kill 1 \
  "interrupted first launch: the app was not running 0 s into its first launch" "**Result: FAILED**" \
  -- FAKE_APP_DIES=1 --

run_case survives_the_kill 1 "the app was still running after kill -9" -- FAKE_IGNORE_KILL=1 FAKE_READY_AFTER_MS=1500 --

run_case never_recovers 1 \
  'relaunch after the kill: no "I am of legal drinking age" within 6 s' "**Result: FAILED**" \
  -- FAKE_READY_AFTER_MS=999999 --
grep -q "What Android does to a running app" "$work/out-never_recovers/resilience.md" \
  && { echo "FAIL never_recovers: the lifecycle checks ran on an app that never recovered"; failures=$((failures + 1)); }

run_case dies_on_a_memory_trim 1 \
  "after a critical memory trim: the app stopped running" -- FAKE_DIES_ON_TRIM=1 FAKE_READY_AFTER_MS=1500 --

run_case trim_refused 0 "the system refused the memory trim, so none was applied" "**Result: passed**" \
  -- FAKE_TRIM_REFUSED=1 FAKE_READY_AFTER_MS=1500 --

run_case kept_alive_in_the_background 0 \
  "the system kept the backgrounded app alive" "**Result: passed**" -- FAKE_KEEP_ALIVE=1 FAKE_READY_AFTER_MS=1500 --

run_case crash_in_logcat 1 "logcat shows a crash, ANR or native-library failure" "UnsatisfiedLinkError" \
  -- FAKE_CRASH=1 FAKE_READY_AFTER_MS=1500 --

# A slow emulator takes seconds to start the process; that is not a stopped app.
run_case slow_start 0 "relaunch after the kill: the first screen was back after" "**Result: passed**" \
  -- RESILIENCE_START_GRACE=10 FAKE_PID_DELAY_MS=2500 FAKE_READY_AFTER_MS=0 -- --interrupt-after 3 --short-timeout 9

run_case no_device 1 "no device is attached" -- FAKE_NO_DEVICE=1 --

run_case install_fails 1 "install failed" -- FAKE_INSTALL_FAIL=1 --

run_case not_installed 1 "com.xaiando.sommelier is not installed" -- FAKE_NOT_INSTALLED=1 -- --no-install

if (( failures )); then echo "$failures case(s) failed."; exit 1; fi
echo "All cases passed."
