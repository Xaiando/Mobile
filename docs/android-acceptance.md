# Android acceptance

How to show that the app works on an Android phone, and what has and has not
been shown so far. The reference phone is a Samsung Galaxy S22 Ultra on
Android 16 / One UI 8. Nothing here is a qualification or an expert review;
it checks that the software behaves.

## What is checked, and by whom

| Question | Checked by | Status |
|---|---|---|
| The APK builds, targets API 36, has no network permission, is signed, and its 64-bit native libraries are 16 KB aligned | `tool/android/verify_apk.py`, run by the *Android runtime* workflow on every build | automatic |
| The app starts on Android 16, installs the curriculum, shows onboarding, survives a second launch and does not crash or ANR | `tool/android/emulator_smoke.sh` on an emulator, in the same workflow | automatic |
| The same on a kernel with 16 KB memory pages (the Play Store's next requirement) | the workflow's second emulator image | automatic |
| A learner can pick a track, study a card, taste and rehearse (the whole `integration_test/app_test.dart` flow) | the same emulator session | automatic |
| Camera capture, gallery picking, OCR on a real label, the system file dialogs, gestures, speed on real hardware, heat, battery | **only the phone** | you, with the list below |
| Anything about the wine facts | a qualified reviewer | never automatic (D3) |

An emulator is not a phone. It proves the app starts and runs on the Android
runtime; it cannot prove that Samsung's camera app, Samsung's gallery, One
UI's back gesture or a 120 Hz screen behave.

## What the first look at the CI build found (154a2a5, 2 October 2026)

An independent read of the `sommelier-android-apk` artifact of run 36965339511:

* `com.xaiando.sommelier` 0.4.0 (17), minSdk 24, targetSdk 36; a 107 MB universal
  APK with arm64-v8a, armeabi-v7a and x86_64 libraries (a phone needs only arm64).
* Native libraries are 16 KB aligned. The camera needs **no** permission: the
  system camera app takes the photo.
* **It held the INTERNET permission**, merged in by `google_mlkit_text_recognition`.
  Google documents that ML Kit sends usage and performance metrics (device
  model, OS version, package name, latency) to Google over HTTPS, even for the
  bundled, on-device text recognition, and offers no way to switch it off
  ([ML Kit data disclosure](https://developers.google.com/ml-kit/android-data-disclosure)).
  The README says "Everything runs offline" and the legal review (L-11) says
  "no telemetry". `android/app/src/release/AndroidManifest.xml` now removes the
  permission from release builds, so Android itself stops the metrics.
  Recognition runs on the phone and does not need the network. Debug and
  profile builds keep INTERNET for the Flutter tool.
* It was signed with a throwaway **debug** key that CI makes afresh on every
  run (see "Updating" below).

## Before you start

1. **Get an APK.** From the *Android runtime* run of the branch you want
   (Actions > the run > Artifacts), download `sommelier-android-arm64-apk`: the
   phone build, about half the size of the universal `sommelier-android-apk`
   that the *CI* run keeps. Or build it yourself with
   `flutter build apk --release --target-platform android-arm64` (needs the
   Android SDK).
2. **Prepare the phone.**
   * Settings > About phone > Software information: tap *Build number* seven
     times. Then Settings > Developer options > *USB debugging* (or *Wireless
     debugging*, which needs no cable).
   * Samsung: Settings > Security and privacy > **Auto Blocker** off. It blocks
     both USB commands and installs from outside the stores.
   * If Play Protect offers to scan the app, choose *Install anyway*.
3. **Run the helper** from the repository folder, with the phone unlocked:

   ```powershell
   powershell -ExecutionPolicy Bypass -File tool\android\accept_device.ps1 `
       -Apk path\to\app-release.apk
   ```

   It checks the APK, installs it, launches it twice and writes a folder
   (`build\android-acceptance\...`) with `summary.md`, a screenshot, `logcat.txt`
   and memory figures. It never taps anything on the phone. Without a cable you
   can install the APK by hand (Files > tap the APK) and skip the helper.
4. **Do onboarding yourself:** confirm your age and choose a track. Then work
   through the list.

## The list

Mark each row pass, fail or a note. "Expected" is what should happen.

### A. Install and start

| # | Do | Expected |
|---|---|---|
| A1 | Install; open the app | Installs; icon labelled *Sommelier*; the first screen appears (the first launch installs the curriculum, which takes the longest; note the seconds from `summary.md`) |
| A2 | Close and reopen | Much faster than the first time |
| A3 | Rotate the phone, if rotation is on | The screen redraws; nothing is lost |
| A4 | Look at the app icon on the home screen and in the app list | A burgundy shape that fills the launcher's icon shape, with a white wine glass: not a small tile on a white plate. With themed icons on (One UI Settings > Wallpaper and style), the glass is tinted to your palette |

### B. Studying

| # | Do | Expected |
|---|---|---|
| B1 | Practice: answer five cards of different kinds | Each shows and grades; the Samsung keyboard does not autocorrect a typed answer into another word |
| B2 | A typed answer, then a short written answer of a few paragraphs | The text field scrolls; the keyboard never hides what you type |
| B3 | A map question: pinch, pan, tap an area | Smooth; a tap near the screen edge does not trigger the system back gesture |
| B4 | Turn on Settings > Display > Font size and style > largest | Text grows; nothing is cut off or overlaps |
| B5 | Dark mode | Readable |

### C. Camera and OCR (Cellar > a wine > photos)

| # | Do | Expected |
|---|---|---|
| C1 | *Scan label*, take a portrait photo of a bottle label with a year and "13.5% vol" | Samsung's camera opens **without any permission prompt**; after the shot you return to the app; the photo appears upright (not sideways) |
| C2 | Read the recognised text | It contains the year and the alcohol level; the *Use vintage* and *Use alcohol* chips offer them; nothing is filled in until you tap |
| C3 | Photograph something with no text | "No label text was recognized." No crash |
| C4 | Take the same label in landscape | Upright too |
| C5 | Dim light, blurry shot | Either some text or the message in C3; no crash |
| C6 | *Photograph glass* | Saved without OCR |

### D. Gallery

| # | Do | Expected |
|---|---|---|
| D1 | *Choose label*; pick a JPEG | The system photo picker opens (no permission prompt); the photo is added and read |
| D2 | Pick a PNG screenshot | Added |
| D3 | Pick a HEIC photo, if your gallery has one (Camera > Settings > Advanced picture options > *High efficiency pictures* on) | The message "Choose a JPEG or PNG photo." |
| D4 | Pick a 108 MP photo (the camera's *108M* mode) | The message about 24 megapixels and 6000 pixels; no crash |

### E. Interruptions

| # | Do | Expected |
|---|---|---|
| E1 | Settings > Developer options > turn **Don't keep activities** on. *Scan label*, take the photo | The app restarts; a banner says a photo selection was interrupted; *Use as label* adds it. Turn the option off afterwards |
| E2 | During a scan, press Home, wait a minute, return | The scan completes or recovers; nothing is duplicated |
| E3 | Start an unsaved wine entry, switch to another app for several minutes | The entry is still there |

### F. Privacy and permissions

| # | Do | Expected |
|---|---|---|
| F1 | Settings > Apps > Sommelier > Permissions | None requested, none granted |
| F2 | Settings > Connections > Data usage, after some use | Sommelier's mobile and Wi-Fi data usage is 0 B: the app holds no network permission |
| F3 | Airplane mode on; use the app, scan a label | Everything works |

### G. Your data

| # | Do | Expected |
|---|---|---|
| G1 | Settings > Your data > Export | The system file dialog opens; save to Downloads; the file exists and is a few KB or more |
| G2 | *Import* that file | Your data returns exactly |
| G3 | Open the exported file in a text app | It contains your photos as text: it is **unencrypted**; the app says so |

### H. Speed and stability

| # | Do | Expected |
|---|---|---|
| H1 | Scroll the Study list and Cellar quickly | No long freezes |
| H2 | Use the app for ten minutes | The phone does not get hot; no crash; `summary.md` memory figures stay sane |
| H3 | Open Home, Practice, Study, Cellar, Tasting, Map and Settings in turn, then press Back repeatedly | Back steps through screens sensibly, then leaves the app; never a blank screen |

## Updating

Android installs an update only over an app signed with the **same key**.
CI builds on pull requests, and on `main` until the release key exists, are
signed with a debug key that is made afresh on every run, so each such APK
refuses to replace the previous one (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`).
Before installing a differently signed build: *Settings > Your data > Export*,
uninstall the old one, install the new one, *Import*.

The lasting fix is the release key: run `tool\android\make_release_key.ps1`
once, yourself (the key must never be created by an agent or committed). From
then on, APKs CI builds on `main` all carry it. Builds from pull requests never
do, by design, because pull-request code must not see the key.

## When something fails

Send the `build\android-acceptance\...` folder, the row number, and what you
saw. For a crash, `logcat.txt` already holds the stack trace. Do not paste
exported backup files: they contain your photos and journal.
