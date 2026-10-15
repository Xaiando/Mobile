#!/usr/bin/env bash
# A fake flutter for the screen tour test: `flutter drive` behaves like a tour
# that asks for FAKE_SHOTS screenshots (names shot1, shot2, ...), prints a
# problem when FAKE_TOUR_PROBLEM=1, and exits with FAKE_DRIVE_STATUS. FAKE_RESIZES is a
# list of window shapes the app asks for in turn, as the resize walk does.
dir=$FAKE_ADB_DIR
touch "$dir/flutter.log"
for i in $(seq 1 "${FAKE_SHOTS:-3}"); do
  echo "TOUR_SHOT shot$i" >> "$dir/flutter.log"
  sleep 1
done
# The app asks the script to change the display (TOUR_RESIZE <shape>) and waits up
# to 8 seconds for its size to change, as the resize walk does.
resize_failed=0
for shape in ${FAKE_RESIZES:-}; do
  before=$(cat "$dir/wm-size" 2>/dev/null || echo none)
  echo "TOUR_RESIZE $shape" >> "$dir/flutter.log"
  changed=0
  for _ in $(seq 1 16); do
    sleep 0.5
    after=$(cat "$dir/wm-size" 2>/dev/null || echo none)
    if [[ $after != "$before" ]]; then changed=1; break; fi
  done
  if (( changed )); then
    echo "TOUR_WINDOW $shape $after" >> "$dir/flutter.log"
  else
    echo "TOUR_PROBLEM resize $shape: the window did not change within 8 s" >> "$dir/flutter.log"
    resize_failed=1
  fi
done
echo "TOUR_TIME light-home 120" >> "$dir/flutter.log"
# FAKE_LOG_LINES: extra lines for the log, separated by |
if [[ -n ${FAKE_LOG_LINES:-} ]]; then
  IFS="|" read -ra extra <<< "$FAKE_LOG_LINES"
  for line in "${extra[@]}"; do echo "$line" >> "$dir/flutter.log"; done
fi
if [[ ${FAKE_TOUR_PROBLEM:-0} == 1 ]]; then
  echo "TOUR_PROBLEM huge study: A RenderFlex overflowed by 24 pixels on the right." >> "$dir/flutter.log"
fi
sleep 1
echo "00:42 +1: All tests passed!"
status=${FAKE_DRIVE_STATUS:-0}
(( resize_failed )) && status=1
exit "$status"
