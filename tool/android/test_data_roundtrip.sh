#!/usr/bin/env bash
# Tests data_roundtrip.sh against the fake adb and fake flutter in testdata/:
#
#   bash tool/android/test_data_roundtrip.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cp "$here/testdata/fake_adb.sh" "$work/bin/adb"
cp "$here/testdata/fake_flutter.sh" "$work/bin/flutter"
chmod +x "$work/bin/adb" "$work/bin/flutter"

failures=0
run_case() { # NAME EXPECTED_STATUS EXPECTED_TEXT... -- ENV...
  local name=$1 expected=$2; shift 2
  local texts=() envs=()
  while [[ ${1:-} != -- ]]; do texts+=("$1"); shift; done; shift
  envs=("$@")
  local out="$work/out-$name"
  rm -rf "$work/state"; mkdir -p "$work/state"
  env PATH="$work/bin:$PATH" FAKE_ADB_DIR="$work/state" FAKE_SHOTS=0 "${envs[@]}" \
    bash "$here/data_roundtrip.sh" "$out" > "$work/log-$name" 2>&1
  local status=$? ok=1
  [[ $status == "$expected" ]] || { ok=0; echo "  exit status $status, expected $expected"; }
  for text in "${texts[@]}"; do
    grep -q -F -- "$text" "$out/summary.md" 2>/dev/null || { ok=0; echo "  summary lacks: $text"; }
  done
  if (( ok )); then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); sed 's/^/     | /' "$work/log-$name" | head -30; fi
}

run_case holds 0 "The round trip found no problems" "**Result: passed**" \
  -- "FAKE_LOG_LINES=ROUNDTRIP_DONE 0 problems"

run_case finds_problems 1 "Problems the round trip found:" "- import: the wine did not come back" \
  "the round trip failed (flutter drive exit status 1)" "**Result: FAILED**" \
  -- "FAKE_LOG_LINES=ROUNDTRIP_PROBLEM import: the wine did not come back|ROUNDTRIP_DONE 1 problems" FAKE_DRIVE_STATUS=1

run_case reports_problems_even_if_drive_passes 1 "- export: the exported file lacks the wine" \
  -- "FAKE_LOG_LINES=ROUNDTRIP_PROBLEM export: the exported file lacks the wine|ROUNDTRIP_DONE 1 problems"

run_case never_finishes 1 "the app printed no ROUNDTRIP_DONE line" "**Result: FAILED**" -- FAKE_DRIVE_STATUS=0

# The app's data is wiped before the drive, so that onboarding is waiting.
rm -rf "$work/state"; mkdir -p "$work/state"
env PATH="$work/bin:$PATH" FAKE_ADB_DIR="$work/state" FAKE_SHOTS=0 "FAKE_LOG_LINES=ROUNDTRIP_DONE 0 problems" \
  bash "$here/data_roundtrip.sh" "$work/out-fresh" > "$work/log-fresh" 2>&1
if grep -q "^shell pm clear com.xaiando.sommelier$" "$work/state/adb-calls.log"; then
  echo "ok   the_apps_data_is_wiped_first"
else
  echo "FAIL the_apps_data_is_wiped_first"; failures=$((failures + 1))
fi

if (( failures )); then echo "$failures case(s) failed."; exit 1; fi
echo "All cases passed."
