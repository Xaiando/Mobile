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
run_case() { # NAME EXPECTED_STATUS EXPECTED_SHOTS EXPECTED_TEXT... -- ENV... [-- SCRIPT_ARGS...]
  local name=$1 expected=$2 shots=$3; shift 3
  local texts=() envs=() args=()
  while [[ ${1:-} != -- ]]; do texts+=("$1"); shift; done; shift
  while [[ $# -gt 0 && $1 != -- ]]; do envs+=("$1"); shift; done
  if [[ ${1:-} == -- ]]; then shift; args=("$@"); fi
  local out="$work/out-$name"
  rm -rf "$work/state"; mkdir -p "$work/state"
  env PATH="$work/bin:$PATH" FAKE_ADB_DIR="$work/state" "${envs[@]}" \
    bash "$here/screen_tour.sh" "${args[@]}" "$out" > "$work/log-$name" 2>&1
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

# The adb calls of the case that ran last.
has_call() { # LABEL TEXT
  if grep -q -F -- "$2" "$work/state/adb-calls.log" 2>/dev/null; then echo "ok   $1"
  else echo "FAIL $1: no adb call containing: $2"; failures=$((failures + 1)); fi
}
lacks_call() { # LABEL TEXT
  if grep -q -F -- "$2" "$work/state/adb-calls.log" 2>/dev/null; then
    echo "FAIL $1: unexpected adb call containing: $2"; failures=$((failures + 1))
  else echo "ok   $1"; fi
}
override() { [[ -f $work/state/wm-size ]] && cat "$work/state/wm-size" || echo none; }

# The Galaxy Z Fold 6's screens: the display is put into the shape before the
# app starts, and given back afterwards.
run_case shape_open 0 2 \
  "window shape: fold-open (Z Fold 6 inner screen unfolded, 1856 x 2160 px" "**Result: passed**" \
  -- FAKE_SHOTS=2 -- --shape fold-open
has_call "the unfolded size was set" "shell wm size 1856x2160"
has_call "the display is given back" "shell wm size reset"
[[ $(override) == none ]] && echo "ok   the display ends without an override" \
  || { echo "FAIL the display still has an override: $(override)"; failures=$((failures + 1)); }
# The size is set after the app's data is wiped and before the tour is driven.
order=$(grep -E "^shell pm clear com.xaiando.sommelier$|^shell wm size 1856x2160$" "$work/state/adb-calls.log" | xargs)
[[ $order == "shell pm clear com.xaiando.sommelier shell wm size 1856x2160" ]] \
  && echo "ok   the shape is set after the wipe" \
  || { echo "FAIL the order of the wipe and the shape: $order"; failures=$((failures + 1)); }

run_case shape_phone 0 1 "window shape: phone (the emulator's own screen)" -- FAKE_SHOTS=1 -- --shape phone
lacks_call "the phone shape overrides nothing" "shell wm size 1"
lacks_call "the phone shape resets nothing" "shell wm size reset"

run_case shape_refused 1 0 \
  "window shape fold-cover: the display did not take 968x2376" "**Result: FAILED**" \
  -- FAKE_SHOTS=3 FAKE_WM_REFUSE=1 -- --shape fold-cover
[[ ! -s $work/state/flutter.log ]] && echo "ok   a refused shape does not drive the tour" \
  || { echo "FAIL the tour was driven although the shape was refused"; failures=$((failures + 1)); }

rm -rf "$work/state"; mkdir -p "$work/state"
env PATH="$work/bin:$PATH" FAKE_ADB_DIR="$work/state" bash "$here/screen_tour.sh" --shape nonsense "$work/out-unknown" > "$work/log-unknown" 2>&1
[[ $? == 2 ]] && echo "ok   an unknown shape is a usage error" \
  || { echo "FAIL an unknown shape is not a usage error"; failures=$((failures + 1)); }

# The resize walk: the app asks for each shape in turn and the script changes
# the display; the windows the app reports go into the summary.
run_case resize_walk 0 1 \
  "The window as the app saw it" "fold-open 1856x2160" "fold-cover 968x2376" \
  "**Result: passed**" \
  -- FAKE_SHOTS=1 "FAKE_RESIZES=fold-open fold-cover phone" -- --resize-walk
has_call "the walk unfolded the display" "shell wm size 1856x2160"
has_call "the walk folded it to the cover" "shell wm size 968x2376"
[[ $(override) == none ]] && echo "ok   the walk ends without an override" \
  || { echo "FAIL the display still has an override after the walk: $(override)"; failures=$((failures + 1)); }

run_case resize_refused 1 1 \
  "the display would not change: fold-open: the display did not take 1856x2160" \
  "resize fold-open: the window did not change" "**Result: FAILED**" \
  -- FAKE_SHOTS=1 FAKE_WM_REFUSE=1 "FAKE_RESIZES=fold-open" -- --resize-walk

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
