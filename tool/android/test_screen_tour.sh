#!/usr/bin/env bash
# Tests screen_tour.sh against the fake adb and fake flutter in testdata/:
#
#   bash tool/android/test_screen_tour.sh
#
# Each case runs the real script and checks its exit status, its report and
# the screenshots it took.
set -u
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cp "$here/testdata/fake_adb.sh" "$work/bin/adb"
cp "$here/testdata/fake_flutter.sh" "$work/bin/flutter"
chmod +x "$work/bin/adb" "$work/bin/flutter"

failures=0
run_case() { # NAME EXPECTED_STATUS EXPECTED_SHOTS EXPECTED_TEXT... -- ENV...
  local name=$1 expected=$2 shots=$3; shift 3
  local texts=() envs=()
  while [[ ${1:-} != -- ]]; do texts+=("$1"); shift; done; shift
  envs=("$@")
  local out="$work/out-$name"
  rm -rf "$work/state"; mkdir -p "$work/state"
  env PATH="$work/bin:$PATH" FAKE_ADB_DIR="$work/state" "${envs[@]}" \
    bash "$here/screen_tour.sh" "$out" > "$work/log-$name" 2>&1
  local status=$? ok=1
  [[ $status == "$expected" ]] || { ok=0; echo "  exit status $status, expected $expected"; }
  local taken
  taken=$(find "$out/shots" -name '*.png' -size +0c 2>/dev/null | wc -l | tr -d ' ')
  [[ $taken == "$shots" ]] || { ok=0; echo "  $taken screenshots, expected $shots"; }
  for text in "${texts[@]}"; do
    grep -q -F -- "$text" "$out/summary.md" 2>/dev/null || { ok=0; echo "  summary lacks: $text"; }
  done
  if (( ok )); then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); sed 's/^/     | /' "$work/log-$name" | head -30; fi
}

run_case passes 0 3 \
  "the tour asked for 3 shots and 3 were taken" "The tour found no problems." \
  "light-home 120" "**Result: passed**" -- FAKE_SHOTS=3

run_case problems_fail_the_tour 1 2 \
  "Problems the tour found:" "A RenderFlex overflowed by 24 pixels" \
  "the tour failed (flutter drive exit status 1)" "**Result: FAILED**" \
  -- FAKE_SHOTS=2 FAKE_TOUR_PROBLEM=1 FAKE_DRIVE_STATUS=1

run_case no_shots 1 0 "no screenshot was taken" "**Result: FAILED**" -- FAKE_SHOTS=0

run_case empty_screenshots 1 0 "no screenshot was taken" -- FAKE_SHOTS=2 FAKE_SCREENCAP_EMPTY=1

if [[ ! -s $work/out-passes/shots/shot2.png ]]; then
  echo "FAIL passes: shot2.png is missing"; failures=$((failures + 1))
fi

# A reused output directory does not carry the last run's pictures into this
# one: a run that took none must fail, not report the old ones as its own.
mkdir -p "$work/out-stale/shots"
printf 'old' > "$work/out-stale/shots/old.png"
rm -rf "$work/state"; mkdir -p "$work/state"
env PATH="$work/bin:$PATH" FAKE_ADB_DIR="$work/state" FAKE_SHOTS=0   bash "$here/screen_tour.sh" "$work/out-stale" > "$work/log-stale" 2>&1
stale_status=$?
if [[ $stale_status == 1 && ! -e $work/out-stale/shots/old.png ]]   && grep -q "no screenshot was taken" "$work/out-stale/summary.md"; then
  echo "ok   stale_shots_are_not_counted"
else
  echo "FAIL stale_shots_are_not_counted (exit $stale_status)"; failures=$((failures + 1))
fi

# Every run starts on a fresh database: the app's data is wiped before the
# tour is driven, never after, and never by uninstalling.
rm -rf "$work/state"; mkdir -p "$work/state"
env PATH="$work/bin:$PATH" FAKE_ADB_DIR="$work/state" FAKE_SHOTS=1   bash "$here/screen_tour.sh" "$work/out-fresh" > "$work/log-fresh" 2>&1
if grep -q "^shell pm clear com.xaiando.sommelier$" "$work/state/adb-calls.log"; then
  echo "ok   the_apps_data_is_wiped_first"
else
  echo "FAIL the_apps_data_is_wiped_first"; failures=$((failures + 1))
fi

if (( failures )); then echo "$failures case(s) failed."; exit 1; fi
echo "All cases passed."
