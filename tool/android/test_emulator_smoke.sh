#!/usr/bin/env bash
# Tests emulator_smoke.sh against a fake adb that behaves like a device:
#
#   bash tool/android/test_emulator_smoke.sh
#
# Each case runs the real script and checks its exit status and report.
set -u
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/state"

cat > "$work/bin/adb" <<'FAKE'
#!/usr/bin/env bash
# A device: FAKE_READY_AFTER_MS until the first screen, FAKE_CRASH=1 for a
# crash in logcat, FAKE_APP_DIES=1 for a process that is gone, FAKE_NO_DEVICE=1
# and FAKE_INSTALL_FAIL=1.
dir=$FAKE_ADB_DIR
now() { date +%s%3N; }
case "$1" in
  get-state)
    if [[ ${FAKE_NO_DEVICE:-0} == 1 ]]; then echo "error: no devices/emulators found"; exit 1; fi
    echo device ;;
  install)
    if [[ ${FAKE_INSTALL_FAIL:-0} == 1 ]]; then
      echo "adb: failed to install: Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE]"
    else
      echo "Performing Streamed Install"; echo "Success"
    fi ;;
  uninstall) echo Success ;;
  logcat)
    if [[ $2 == -d ]]; then
      echo "10-02 12:00:00.000  1000  1000 I flutter : engine started"
      if [[ ${FAKE_CRASH:-0} == 1 ]]; then
        echo "10-02 12:00:03.000  1234  1234 E AndroidRuntime: FATAL EXCEPTION: main"
        echo "10-02 12:00:03.000  1234  1234 E AndroidRuntime: Process: com.xaiando.sommelier, PID: 1234"
        echo "10-02 12:00:03.000  1234  1234 E AndroidRuntime: java.lang.UnsatisfiedLinkError: libsqlite3.so"
      fi
      echo "10-02 12:00:04.000  1234  1300 W CctTransportBackend: java.net.SocketException: socket failed: EACCES (Permission denied)"
    fi ;;
  exec-out)
    case "$2" in
      uiautomator)
        started=$(cat "$dir/started" 2>/dev/null || echo 0)
        echo '<?xml version="1.0"?><hierarchy rotation="0">'
        if (( $(now) - started >= ${FAKE_READY_AFTER_MS:-0} )); then
          echo '<node text="" content-desc="I am of legal drinking age where I live." />'
        else
          echo '<node text="" content-desc="" />'
        fi
        echo '</hierarchy>'
        echo 'UI hierchary dumped to: /dev/tty' ;;
      screencap) printf '\211PNG fake' ;;
    esac ;;
  shell)
    case "$2" in
      getprop)
        case "$3" in
          ro.product.model) echo "Pixel Fake" ;;
          ro.build.version.release) echo 16 ;;
          ro.build.version.sdk) echo 36 ;;
          ro.product.cpu.abi) echo x86_64 ;;
          ro.build.fingerprint) echo "google/fake/fake:16/BP1A:user/release-keys" ;;
        esac ;;
      getconf) echo "${FAKE_PAGE_SIZE:-4096}" ;;
      dumpsys)
        case "$3" in
          package) echo "    versionName=0.4.0"; echo "    targetSdk=36" ;;
          meminfo) echo "  Native Heap    20000"; echo "  TOTAL PSS:   250000"; echo "  TOTAL RSS:   400000" ;;
        esac ;;
      am)
        case "$3" in
          force-stop) rm -f "$dir/running" ;;
          start)
            now > "$dir/started"
            [[ ${FAKE_APP_DIES:-0} == 1 ]] || touch "$dir/running"
            echo "Starting: Intent { cmp=com.xaiando.sommelier/.MainActivity }"
            echo "Status: ok"; echo "TotalTime: 1234"; echo "WaitTime: 1250" ;;
        esac ;;
      pidof) [[ -f $dir/running ]] && echo 1234 ;;
    esac ;;
esac
exit 0
FAKE
chmod +x "$work/bin/adb"

failures=0
run_case() { # NAME EXPECTED_STATUS EXPECTED_TEXT... -- ENV... -- SCRIPT_ARGS...
  local name=$1 expected=$2; shift 2
  local texts=() envs=() args=()
  while [[ ${1:-} != -- ]]; do texts+=("$1"); shift; done; shift
  while [[ ${1:-} != -- ]]; do envs+=("$1"); shift; done; shift
  args=("$@")
  local out="$work/out-$name"
  rm -rf "$work/state"; mkdir -p "$work/state"
  env PATH="$work/bin:$PATH" FAKE_ADB_DIR="$work/state" "${envs[@]}" \
    bash "$here/emulator_smoke.sh" --timeout 6 "${args[@]}" fake.apk "$out" > "$work/log-$name" 2>&1
  local status=$?
  local ok=1
  [[ $status == "$expected" ]] || { ok=0; echo "  exit status $status, expected $expected"; }
  for text in "${texts[@]}"; do
    grep -q -F -- "$text" "$out/summary.md" 2>/dev/null || { ok=0; echo "  summary lacks: $text"; }
  done
  if (( ok )); then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); sed 's/^/     | /' "$work/log-$name" | head -30; fi
}

run_case success 0 \
  "Pixel Fake" "android:  16 (API 36)" "page:     4096 bytes" \
  "first launch: window drawn after 1234 ms" "second launch:" \
  "no crash, ANR or native-library failure in logcat" \
  "network attempts the system refused (expected without INTERNET): 1" \
  "TOTAL PSS" "**Result: passed**" -- FAKE_READY_AFTER_MS=1500 --
[[ -s $work/out-success/first-launch.png ]] || { echo "FAIL success: no screenshot"; failures=$((failures + 1)); }

run_case sixteen_kb_pages 0 "page:     16384 bytes" -- FAKE_PAGE_SIZE=16384 --

run_case never_ready 1 'FAIL** first launch: no "I am of legal drinking age" within 6 s' \
  "**Result: FAILED**" -- FAKE_READY_AFTER_MS=999999 --

run_case crash 1 "logcat shows a crash, ANR or native-library failure" \
  "UnsatisfiedLinkError" "**Result: FAILED**" -- FAKE_CRASH=1 FAKE_READY_AFTER_MS=0 --

run_case app_dies 1 "first launch: the app stopped running" -- FAKE_APP_DIES=1 --

run_case install_fails 1 "install failed" "INSTALL_FAILED_UPDATE_INCOMPATIBLE" \
  "Export your data in the app first" -- FAKE_INSTALL_FAIL=1 --

run_case no_device 1 "no device is attached" -- FAKE_NO_DEVICE=1 --

run_case no_install_option 0 "**Result: passed**" -- FAKE_INSTALL_FAIL=1 FAKE_READY_AFTER_MS=0 -- --no-install

run_case custom_ready_text 0 "**Result: passed**" -- FAKE_READY_AFTER_MS=0 -- --ready "legal drinking age"

if (( failures )); then echo "$failures case(s) failed."; exit 1; fi
echo "All cases passed."
