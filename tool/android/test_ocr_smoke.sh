#!/usr/bin/env bash
# Tests ocr_smoke.sh against the fake adb in testdata/:
#
#   bash tool/android/test_ocr_smoke.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cp "$here/testdata/fake_adb.sh" "$work/bin/adb"
chmod +x "$work/bin/adb"

failures=0
run_case() { # NAME EXPECTED_STATUS EXPECTED_TEXT... -- ENV...
  local name=$1 expected=$2; shift 2
  local texts=() envs=()
  while [[ ${1:-} != -- ]]; do texts+=("$1"); shift; done; shift
  envs=("$@")
  local out="$work/out-$name"
  rm -rf "$work/state"; mkdir -p "$work/state"
  env PATH="$work/bin:$PATH" FAKE_ADB_DIR="$work/state" FAKE_READY_AFTER_MS=0 "${envs[@]}" \
    bash "$here/ocr_smoke.sh" fake.apk "$out" > "$work/log-$name" 2>&1
  local status=$? ok=1
  [[ $status == "$expected" ]] || { ok=0; echo "  exit status $status, expected $expected"; }
  for text in "${texts[@]}"; do
    grep -q -F -- "$text" "$out/ocr.md" 2>/dev/null || { ok=0; echo "  report lacks: $text"; }
  done
  if (( ok )); then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); sed 's/^/     | /' "$work/log-$name" | head -20; fi
}

run_case reads_the_label 0 "GRAND VIN 2019" "**Result: passed**" -- FAKE_OCR=ok
run_case wrong_text 1 "the vintage 2019 was not found" "the alcohol level 14.5 % was not found" \
  "**Result: FAILED**" -- FAKE_OCR=wrong
run_case recognition_error 1 "text recognition raised an error" -- FAKE_OCR=error
run_case plugin_error 1 "the image_picker plugin did not answer" "**Result: FAILED**" -- FAKE_OCR=plugin_error
run_case no_line 1 "the app logged no OCR_CHECK line" -- FAKE_OCR=none FAKE_APP_DIES=1
run_case crash 1 "logcat shows a crash or a native-library failure" -- FAKE_OCR=ok FAKE_CRASH=1
run_case no_device 1 "no device is attached" -- FAKE_NO_DEVICE=1
run_case install_fails 1 "install failed" -- FAKE_INSTALL_FAIL=1

if (( failures )); then echo "$failures case(s) failed."; exit 1; fi
echo "All cases passed."
