#!/usr/bin/env bash
# Runs tool/android_smoke on the connected emulator or phone: it draws a wine
# label, recognizes it with ML Kit through the cellar's own function, calls
# the image_picker and file_picker plugins with requests that need no screen,
# and logs one OCR_CHECK line. This script reads that line and passes only if
# the vintage 2019 and the alcohol level 14.5 % came back and both plugins
# answered.
#
#   flutter build apk --release -t tool/android_smoke/main.dart \
#       --target-platform android-x64          # android-arm64 for a phone
#   tool/android/ocr_smoke.sh [--uninstall-after] APK OUTPUT_DIR
#
# It replaces any installed copy of the app (same package), so on a phone with
# your data on it, do not use it: build it for an emulator. Writes
# OUTPUT_DIR/ocr.md. Exit status: 0 when recognition worked, 1 otherwise.
set -u

uninstall_after=0
if [[ ${1:-} == --uninstall-after ]]; then uninstall_after=1; shift; fi
apk=${1:?usage: $0 [--uninstall-after] APK OUTPUT_DIR}
out=${2:?usage: $0 [--uninstall-after] APK OUTPUT_DIR}
package=com.xaiando.sommelier
mkdir -p "$out"
report=$out/ocr.md
status=0

adbq() { timeout 60 adb "$@" 2>&1 | tr -d '\r'; }
note() { echo "$*" | tee -a "$report"; }

: > "$report"
note "# Text recognition check"
note ""
if [[ $(adbq get-state) != device ]]; then
  note "- **FAIL** no device is attached"
  exit 1
fi
result=$(adbq install -r -t "$apk")
if [[ $result != *Success* ]]; then
  note "- **FAIL** install failed: $result"
  exit 1
fi

adbq logcat -c > /dev/null
adbq shell am start -W -n "$package/.MainActivity" > /dev/null
line=
for _ in $(seq 1 60); do
  line=$(adbq logcat -d -s flutter:I | grep -m1 'OCR_CHECK')
  [[ -n $line ]] && break
  if [[ -z $(adbq shell pidof "$package") ]]; then break; fi
  sleep 2
done
adbq logcat -d > "$out/ocr-logcat.txt"

if [[ -z $line ]]; then
  note "- **FAIL** the app logged no OCR_CHECK line (it stopped, or never finished)"
  status=1
else
  json=${line#*OCR_CHECK }
  note "- ML Kit read the label: \`$json\`"
  if [[ $json == *'"error"'* ]]; then
    note "- **FAIL** text recognition raised an error"
    status=1
  fi
  [[ $json == *'"vintage":2019'* ]] || { note "- **FAIL** the vintage 2019 was not found"; status=1; }
  [[ $json == *'"abv":14.5'* ]] || { note "- **FAIL** the alcohol level 14.5 % was not found"; status=1; }
  for plugin in image_picker file_picker; do
    [[ $json == *"\"$plugin\":\"ok\""* ]] || { note "- **FAIL** the $plugin plugin did not answer"; status=1; }
  done
fi
if grep -E -q 'FATAL EXCEPTION|Fatal signal|UnsatisfiedLinkError' "$out/ocr-logcat.txt"; then
  note "- **FAIL** logcat shows a crash or a native-library failure"
  status=1
fi

if (( uninstall_after )); then adbq uninstall "$package" > /dev/null; fi
note ""
if (( status )); then note "**Result: FAILED**"; else note "**Result: passed**"; fi
[[ -n ${GITHUB_STEP_SUMMARY:-} ]] && cat "$report" >> "$GITHUB_STEP_SUMMARY"
exit $status
