#!/usr/bin/env bash
# Window shapes for an emulator, so that a phone-sized emulator can stand in
# for the screens of a foldable phone. Sourced by screen_tour.sh and
# resilience.sh; not run on its own:
#
#   . "$(dirname "$0")/window_shape.sh"
#   set_shape fold-open || echo "$SHAPE_ERROR"
#   reset_shape
#
# The shapes are the Samsung Galaxy Z Fold 6's two displays at its default
# 420 dpi, in pixels, with the same sizes in dp (px / 2.625) beside them:
#
#   phone           the emulator's own screen; nothing is overridden
#   fold-cover      the cover screen, 968 x 2376 (369 x 905 dp)
#   fold-open       the inner screen unfolded, 1856 x 2160 (707 x 823 dp)
#   fold-open-wide  the inner screen turned sideways, 2160 x 1856 (823 x 707 dp)
#   fold-split      half the inner screen's width, as in split screen,
#                   928 x 2160 (354 x 823 dp)
#
# The same sizes are in tool/android_tour/tour.dart (foldWindowSizes) for the
# desktop test; change them together.
#
# `adb shell wm size` overrides the display size of a running device. To an app
# that is what folding is: its window gets another size and the activity gets a
# configuration change, which the manifest's configChanges tells the activity to
# handle itself. It is not the hinge, the postures (Flex mode) or anything that
# Samsung adds on top; those are for the phone. Android refuses a size beyond
# twice the display's own, and the Pixel 6 profile's 1080 x 2400 only just
# holds the widest shape.

SHAPE_ERROR=

shape_size() { # NAME: prints WIDTHxHEIGHT in pixels, or fails for an unknown name
  case $1 in
    fold-cover) echo 968x2376 ;;
    fold-open) echo 1856x2160 ;;
    fold-open-wide) echo 2160x1856 ;;
    fold-split) echo 928x2160 ;;
    *) return 1 ;;
  esac
}

shape_label() { # NAME: what the shape stands for
  case $1 in
    phone) echo "the emulator's own screen" ;;
    fold-cover) echo "Z Fold 6 cover screen, 968 x 2376 px, about 369 x 905 dp" ;;
    fold-open) echo "Z Fold 6 inner screen unfolded, 1856 x 2160 px, about 707 x 823 dp" ;;
    fold-open-wide) echo "Z Fold 6 inner screen sideways, 2160 x 1856 px, about 823 x 707 dp" ;;
    fold-split) echo "half the Z Fold 6 inner screen, 928 x 2160 px, about 354 x 823 dp" ;;
    *) echo "unknown shape $1"; return 1 ;;
  esac
}

shape_known() { [[ $1 == phone ]] || shape_size "$1" > /dev/null; }

shape_adb() { timeout 30 adb shell "$@" 2>&1 | tr -d '\r'; }

# Puts the display into shape NAME. Fails, with SHAPE_ERROR set, when the
# emulator will not take it.
set_shape() { # NAME
  local name=$1 size density now
  SHAPE_ERROR=
  if [[ $name == phone ]]; then
    reset_shape
    return 0
  fi
  if ! size=$(shape_size "$name"); then
    SHAPE_ERROR="unknown window shape $name"
    return 1
  fi
  # The Fold's screens are 420 dpi, which the Pixel 6 profile already is.
  density=$(shape_adb wm density | sed -n 's/^Physical density: *//p')
  if [[ -n $density && $density != 420 ]]; then shape_adb wm density 420 > /dev/null; fi
  shape_adb wm size "$size" > /dev/null
  now=$(shape_adb wm size)
  if [[ $now != *"Override size: $size"* ]]; then
    SHAPE_ERROR="the display did not take $size: $(echo "$now" | tr '\n' ' ')"
    return 1
  fi
  return 0
}

# Gives the display back its own size and density. Harmless when nothing was
# overridden.
reset_shape() {
  shape_adb wm size reset > /dev/null
  shape_adb wm density reset > /dev/null
}
