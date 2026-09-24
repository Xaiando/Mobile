#!/usr/bin/env bash
# Google Play requires 16 KB page-size support for apps targeting Android 15+.
# Every 64-bit native library in the APK must have LOAD segments aligned to at
# least 16 KB, and must be stored 16 KB-aligned inside the APK.
#
#   tool/check_16kb_alignment.sh build/app/outputs/flutter-apk/app-release.apk
set -euo pipefail

apk=${1:?usage: $0 path/to/app.apk}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if ! unzip -q "$apk" 'lib/*' -d "$work" 2>/dev/null; then
  echo "No native libraries in $apk."
  exit 0
fi

status=0
checked=0
while IFS= read -r library; do
  checked=$((checked + 1))
  for align in $(readelf -lW "$library" | awk '$1 == "LOAD" { print $NF }'); do
    if (( align < 0x4000 )); then
      echo "FAIL ${library#"$work"/}: LOAD segment aligned to $align (needs 0x4000)"
      status=1
    fi
  done
done < <(find "$work/lib" -name '*.so' \( -path '*/arm64-v8a/*' -o -path '*/x86_64/*' \))

zipalign=$(ls -d "${ANDROID_HOME:?ANDROID_HOME is not set}"/build-tools/*/zipalign 2>/dev/null | sort -V | tail -1)
if [[ -z "$zipalign" ]]; then
  echo "FAIL zipalign not found under $ANDROID_HOME/build-tools"
  status=1
elif ! "$zipalign" -c -P 16 4 "$apk"; then
  echo "FAIL native libraries are not 16 KB-aligned inside the APK"
  status=1
fi

if (( status == 0 )); then
  echo "16 KB alignment OK for $checked native libraries in $(basename "$apk")."
fi
exit $status
