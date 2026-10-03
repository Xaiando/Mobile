#!/usr/bin/env bash
# A fake flutter for the screen tour test: `flutter drive` behaves like a tour
# that asks for FAKE_SHOTS screenshots (names shot1, shot2, ...), prints a
# problem when FAKE_TOUR_PROBLEM=1, and exits with FAKE_DRIVE_STATUS.
dir=$FAKE_ADB_DIR
touch "$dir/flutter.log"
for i in $(seq 1 "${FAKE_SHOTS:-3}"); do
  echo "TOUR_SHOT shot$i" >> "$dir/flutter.log"
  sleep 1
done
echo "TOUR_TIME light-home 120" >> "$dir/flutter.log"
if [[ ${FAKE_TOUR_PROBLEM:-0} == 1 ]]; then
  echo "TOUR_PROBLEM huge study: A RenderFlex overflowed by 24 pixels on the right." >> "$dir/flutter.log"
fi
sleep 1
echo "00:42 +1: All tests passed!"
exit "${FAKE_DRIVE_STATUS:-0}"
