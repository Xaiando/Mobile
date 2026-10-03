#!/usr/bin/env bash
# Tests emulator_smoke.sh against a fake adb that behaves like a device:
#
#   bash tool/android/test_emulator_smoke.sh
#
# Each case runs the real script and checks its exit status and report.
set -u
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/state"

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
  env PATH="$work/bin:$PATH" FAKE_ADB_DIR="$work/state" "${envs[@]}" \
    bash "$here/emulator_smoke.sh" --timeout 6 "${args[@]}" fake.apk "$out" > "$work/log-$name" 2>&1
  local status=$?
  local ok=1
  [[ $status == "$expected" ]] || { ok=0; echo "  exit status $status, expected $expected"; }
  for text in "${texts[@]}"; do
    grep -q -F -- "$text" "$out/summary.md" 2>/dev/null || { ok=0; echo "  summary lacks: $text"; }
  done
  if (( ok )); then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); sed 's/^/     | /' "$work/log-$name" | head -30; fi
}

run_case success 0 \
  "Pixel Fake" "android:  16 (API 36)" "page:     4096 bytes" \
  "first launch: window drawn after 1234 ms" "the app used 14.7 s of CPU and held at most 340 MB in memory" "second launch:" \
  "no crash, ANR or native-library failure in logcat" "ML Kit started its components" \
  "network attempts the system refused (expected without INTERNET): 1" \
  "TOTAL PSS" "**Result: passed**" -- FAKE_READY_AFTER_MS=1500 --
[[ -s $work/out-success/first-launch.png ]] || { echo "FAIL success: no screenshot"; failures=$((failures + 1)); }

run_case sixteen_kb_pages 0 "page:     16384 bytes" -- FAKE_PAGE_SIZE=16384 --

run_case never_ready 1 'FAIL** first launch: no "I am of legal drinking age" within 6 s' \
  "**Result: FAILED**" -- FAKE_READY_AFTER_MS=999999 --

run_case crash 1 "logcat shows a crash, ANR or native-library failure" \
  "UnsatisfiedLinkError" "**Result: FAILED**" -- FAKE_CRASH=1 FAKE_READY_AFTER_MS=0 --

run_case app_dies 1 "first launch: the app stopped running" -- FAKE_APP_DIES=1 SMOKE_START_GRACE=1 --

# A slow emulator takes seconds to start the process; that is not a stopped app.
run_case slow_start 0 "first launch: window drawn after 1234 ms" "**Result: passed**" -- FAKE_PID_DELAY_MS=3000 FAKE_READY_AFTER_MS=0 --

run_case ml_kit_registrar 1 "ML Kit could not start its components"   "CommonComponentRegistrar" "**Result: FAILED**" -- FAKE_REGISTRAR=1 FAKE_READY_AFTER_MS=0 --

run_case install_fails 1 "install failed" "INSTALL_FAILED_UPDATE_INCOMPATIBLE" \
  "Export your data in the app first" -- FAKE_INSTALL_FAIL=1 --

run_case no_device 1 "no device is attached" -- FAKE_NO_DEVICE=1 --

run_case no_install_option 0 "**Result: passed**" -- FAKE_INSTALL_FAIL=1 FAKE_READY_AFTER_MS=0 -- --no-install

run_case control 0 "control (data wiped, checked only at 2 4 s): first screen seen by 2 s"   "**Result: passed**" -- FAKE_READY_AFTER_MS=0 -- --uninstall-after --control --checkpoints "2 4"

run_case control_not_ready 0 "first screen **not** seen by the last checkpoint"   -- FAKE_READY_AFTER_MS=1500 -- --uninstall-after --control --checkpoints "0"

run_case custom_ready_text 0 "**Result: passed**" -- FAKE_READY_AFTER_MS=0 -- --ready "legal drinking age"

env PATH="$work/bin:$PATH" FAKE_ADB_DIR="$work/state" bash "$here/emulator_smoke.sh" --control fake.apk "$work/out-refuse" > "$work/log-refuse" 2>&1
if [[ $? == 2 ]] && grep -q "wipes the app's data" "$work/log-refuse"; then
  echo "ok   control_refused_without_uninstall_after"
else
  echo "FAIL control_refused_without_uninstall_after"; failures=$((failures + 1))
fi

if (( failures )); then echo "$failures case(s) failed."; exit 1; fi
echo "All cases passed."
