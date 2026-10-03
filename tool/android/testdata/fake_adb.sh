#!/usr/bin/env bash
# A fake adb for the script tests: it behaves like a device.
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
    if [[ ${3:-} == -s ]]; then
      started=$(cat "$dir/started" 2>/dev/null || echo 0)
      # FAKE_OCR_AFTER_MS: the check app prints its line some time after it starts.
      if (( $(now) - started < ${FAKE_OCR_AFTER_MS:-0} )); then exit 0; fi
      case ${FAKE_OCR:-none} in
        ok) echo '10-02 12:00:05.000  1234  1234 I flutter : OCR_CHECK {"text":"CHATEAU EXEMPLE | GRAND VIN 2019 | ALC. 14.5% VOL.","vintage":2019,"abv":14.5,"warnings":[],"plugins":{"image_picker":"ok","file_picker":"ok"},"ms":812}' ;;
        plugin_error) echo '10-02 12:00:05.000  1234  1234 I flutter : OCR_CHECK {"text":"CHATEAU EXEMPLE | GRAND VIN 2019 | ALC. 14.5% VOL.","vintage":2019,"abv":14.5,"warnings":[],"plugins":{"image_picker":"error: MissingPluginException(No implementation found)","file_picker":"ok"},"ms":812}' ;;
        wrong) echo '10-02 12:00:05.000  1234  1234 I flutter : OCR_CHECK {"text":"CHATEAU","vintage":null,"abv":null,"warnings":["no_text"],"ms":900}' ;;
        error) echo '10-02 12:00:05.000  1234  1234 I flutter : OCR_CHECK {"error":"PlatformException(MlKitException)","ms":50}' ;;
      esac
    elif [[ $2 == -d ]]; then
      echo "10-02 12:00:00.000  1000  1000 I flutter : engine started"
      if [[ ${FAKE_CRASH:-0} == 1 ]]; then
        echo "10-02 12:00:03.000  1234  1234 E AndroidRuntime: FATAL EXCEPTION: main"
        echo "10-02 12:00:03.000  1234  1234 E AndroidRuntime: Process: com.xaiando.sommelier, PID: 1234"
        echo "10-02 12:00:03.000  1234  1234 E AndroidRuntime: java.lang.UnsatisfiedLinkError: libsqlite3.so"
      fi
      if [[ ${FAKE_REGISTRAR:-0} == 1 ]]; then
        echo "10-02 12:00:01.000  1234  1234 W ComponentDiscovery: mi: Could not instantiate com.google.mlkit.common.internal.CommonComponentRegistrar"
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
      cat)
        case "$3" in
          */status) echo "Name: sommelier"; echo "VmPeak:  2000000 kB"; echo "VmHWM:    348160 kB"; echo "VmRSS:    300000 kB" ;;
          *) echo "1234 (com.xaiando.sommelier) S 1 1 1 0 0 0 0 0 0 0 1234 234 0 0 20 0 30 0 100 0 0" ;;
        esac ;;
      dumpsys)
        case "$3" in
          package)
            echo "    versionName=0.4.0"; echo "    targetSdk=36"
            echo "    requested permissions:"
            echo "      android.permission.ACCESS_NETWORK_STATE"
            echo "    install permissions:"
            echo "      android.permission.ACCESS_NETWORK_STATE: granted=true"
            echo "    User 0: installed=true"
            echo "      runtime permissions:"
            if [[ ${FAKE_RUNTIME_PERMISSION:-0} == 1 ]]; then
              echo "        android.permission.CAMERA: granted=true, flags=[ USER_SET]"
            fi ;;
          cpuinfo) echo "Load: 2.5 / 2.0 / 1.0"; echo "  120% 1234/com.xaiando.sommelier: 100% user + 20% kernel" ;;
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
      pidof)
        # FAKE_PID_DELAY_MS: a slow emulator takes a while to start the process.
        if [[ -f $dir/running ]]; then
          started=$(cat "$dir/started" 2>/dev/null || echo 0)
          if (( $(now) - started >= ${FAKE_PID_DELAY_MS:-0} )); then echo 1234; fi
        fi ;;
      pm) rm -f "$dir/running" ;;
    esac ;;
esac
exit 0
