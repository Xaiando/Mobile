#!/usr/bin/env bash
# Tests window_shape.sh against the fake adb in testdata/:
#
#   bash tool/android/test_window_shape.sh
#
# The helper is sourced by screen_tour.sh and resilience.sh, so these cases
# call its functions directly.
set -u
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/state"
cp "$here/testdata/fake_adb.sh" "$work/bin/adb"
chmod +x "$work/bin/adb"
export PATH="$work/bin:$PATH" FAKE_ADB_DIR="$work/state"
# shellcheck source=window_shape.sh
. "$here/window_shape.sh"

failures=0
check() { # NAME EXPECTED ACTUAL
  if [[ $2 == "$3" ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    echo "     expected: $2"
    echo "     actual:   $3"
    failures=$((failures + 1))
  fi
}
fresh() { rm -rf "$work/state"; mkdir -p "$work/state"; unset FAKE_WM_REFUSE FAKE_DENSITY; }
display() { adb shell wm size | tr -d '\r' | tr '\n' ' '; }

check "cover size" 968x2376 "$(shape_size fold-cover)"
check "open size" 1856x2160 "$(shape_size fold-open)"
check "open sideways size" 2160x1856 "$(shape_size fold-open-wide)"
check "split size" 928x2160 "$(shape_size fold-split)"
shape_size nonsense > /dev/null; check "an unknown shape has no size" 1 $?
shape_known phone; check "phone is a shape" 0 $?
shape_known fold-open; check "fold-open is a shape" 0 $?
shape_known nonsense; check "nonsense is not a shape" 1 $?
check "label of the cover screen" \
  "Z Fold 6 cover screen, 968 x 2376 px, about 369 x 905 dp" "$(shape_label fold-cover)"

# The dp sizes in the labels are the pixel sizes at 420 dpi (2.625 px per dp).
for name in fold-cover fold-open fold-open-wide fold-split; do
  size=$(shape_size "$name")
  w=${size%x*}; h=${size#*x}
  dp=$(awk -v w="$w" -v h="$h" 'BEGIN { printf "%d x %d dp", w / 2.625 + 0.5, h / 2.625 + 0.5 }')
  [[ $(shape_label "$name") == *"$dp"* ]] \
    && echo "ok   $name label states its dp size ($dp)" \
    || { echo "FAIL $name label does not state $dp: $(shape_label "$name")"; failures=$((failures + 1)); }
done

fresh
set_shape fold-open
check "set_shape fold-open succeeds" 0 $?
check "the display took the unfolded size" "Physical size: 1080x2400 Override size: 1856x2160 " "$(display)"
grep -q "wm density 420" "$work/state/adb-calls.log" \
  && { echo "FAIL a 420 dpi display had its density set"; failures=$((failures + 1)); } \
  || echo "ok   a 420 dpi display keeps its density"

set_shape fold-cover
check "the next shape replaces the last" "Physical size: 1080x2400 Override size: 968x2376 " "$(display)"

set_shape phone
check "phone gives the display back" "Physical size: 1080x2400 " "$(display)"

fresh
export FAKE_DENSITY=440
set_shape fold-split
check "a 440 dpi display is set to the Fold's 420" 1 "$(grep -c "wm density 420" "$work/state/adb-calls.log")"
reset_shape
check "reset_shape clears size" "Physical size: 1080x2400 " "$(display)"
check "reset_shape clears density" "" "$(ls "$work/state" | grep -c '^wm-density$' | sed 's/^0$//')"

fresh
set_shape nonsense
check "an unknown shape fails" 1 $?
check "an unknown shape says so" "unknown window shape nonsense" "$SHAPE_ERROR"

fresh
export FAKE_WM_REFUSE=1
set_shape fold-open
check "a display that refuses fails" 1 $?
case $SHAPE_ERROR in
  *"did not take 1856x2160"*) echo "ok   a refusal says what was refused" ;;
  *) echo "FAIL a refusal does not say what was refused: $SHAPE_ERROR"; failures=$((failures + 1)) ;;
esac

if (( failures )); then echo "$failures case(s) failed."; exit 1; fi
echo "All cases passed."
