# Android scanner device acceptance

Prepared 30 September 2026. **All device checks below are UNRUN.** The user reports a Samsung Galaxy S22 Ultra running Android 16 / One UI 8; device properties have not been read and an iPhone is unavailable. Native capture/OCR/cleanup need observed device evidence. iPhone and native HEIC checks remain unobserved.

## Record before starting

| Evidence | Actual value |
| --- | --- |
| Tester; session start/end UTC | _pending_ |
| Android device model; Android version/API | Samsung Galaxy S22 Ultra, Android 16 / One UI 8 (user-reported); device-read version/API _pending_ |
| PR head; actual CI checkout/merge SHA; run ID; APK filename and SHA-256 | Captured for PR 45/run 36708753882; exact provenance and APK hash appear below. Installation/signature evidence remains _pending_. |
| Installed app version/build; install/update outcome | _pending_ |
| Input labels/images; orientation/format; network state | _pending_ |
| Each check's UTC time; PASS/FAIL/UNRUN; screenshot/error | _pending_ |

Record the fixed candidate commit, actual CI checkout SHA, run ID and APK hash: the version alone cannot identify these fixes. A pull-request workflow normally checks out its synthetic merge commit, so the branch head alone is insufficient artifact provenance. Current app: `com.xaiando.sommelier`, `0.4.0+17`, Android API 24+. Export personal data before any incompatible-signature reinstall; uninstall/clear-storage removes it. Use disposable entries for erase/restore.

## Device checklist

Open **Cellar → Log a wine**. Use a clear Latin-script label such as `Test Estate 2019 13.5%` and a separate glass photo. Record the actual recognized text.

| Check | Action and required observation | Result |
| --- | --- | --- |
| Camera and gallery | Use **Scan label**, **Choose label**, **Photograph glass** and **Choose glass**. Capture upright and rotated images; saved previews must be upright and attached to the chosen kind. | UNRUN |
| Permission and cancel | Deny/allow permission where Android prompts, then retry. Cancel camera/gallery: existing draft/photos must remain. Record absent prompts accurately; Photo Picker behavior varies. | UNRUN |
| Offline Latin OCR | Use airplane mode with Wi-Fi off. Capture afresh; record recognition, elapsed time and text. OCR failure must allow photo use/manual entry. | UNRUN |
| Explicit proposals | Vintage/ABV change only after accepting a chip. Correct them manually; enter names yourself. Two year tokens or `100.5%` must withhold ambiguous/unsupported proposals. | UNRUN |
| Manual precedence | Edit the transcript and replace the label: preserve manual text. Edit during recognition if possible; late OCR must not overwrite it. Otherwise mark that subcheck UNRUN. | UNRUN |
| Save gate | Save both photos; pending-save controls must disable and saved values match. If too fast to observe, leave the pending-state subcheck UNRUN. | UNRUN |
| Interrupted picker | Reproduce app/activity reclamation during camera/gallery, then return the selected image. Check **Recovered photo**; use it, leave unsaved and reopen: retain recovery. If unreproducible safely, mark UNRUN. | UNRUN |
| Recovery completion | Successful save persists the recovered photo and clears its queue entry. Explicitly dismiss a second disposable recovery: clear that copy. | UNRUN |
| Failed-save retry | Use a diagnostic one-shot write failure: retain draft/photo/recovery after the error; retry saves exact contents and clears recovery once. Release UI has no fault injection; without a safe failure, mark UNRUN. | UNRUN |
| Restart persistence | Close/reopen after successful save. Check vintage/ABV and both photos on the exact entry, then edit or replace one photo without changing the other. | UNRUN |
| Backup and restore | **Settings → Your data → Export your data**; keep the unencrypted file private. Restore disposable data with **Import a backup**; verify fields/both photos. Unsaved recovery is not exported. | UNRUN |
| Guarded cleanup and erase | On a debuggable APK, inspect private cache/staging before/after use, dismiss, **Erase all data** and restart. Owned copies must clear; gallery originals remain. If private paths cannot be inspected, mark UNRUN; an empty journal is insufficient. | UNRUN |

Record actual process-death reproduction; ordinary restart is insufficient. Restore changed Developer options. Do not fill personal storage to force errors. Keep failures/unknowns alongside passes.

## Read-only build availability on this host

- Flutter/Dart exist under `D:\tools\flutter`; JDK 21 is present. The initial availability inspection ran no SDK command, build or device probe. A later existing-platform-tools check at `08:33 UTC` returned no attached USB device; no app was installed or changed.
- NEXT has no `android/local.properties`; `ANDROID_HOME` and `ANDROID_SDK_ROOT` are unset. The original checkout's SDK path points at the WinGet Platform Tools package, containing `platform-tools/adb.exe` but no `cmdline-tools`, `platforms`, `build-tools`, `ndk` or `licenses`. The standard local Android SDK directory is absent. A complete configured Android SDK is therefore a local-build blocker.
- Pinned defaults require compile/target SDK 36 and NDK `28.2.13676358`. Nothing was installed or licensed.
- At the initial inspection, no existing APK was found in the active or original checkout's build trees, including standard Flutter APK paths. A CI APK was subsequently downloaded as recorded below; the initial absence is historical.
- CI uploads **sommelier-android-apk** containing `build/app/outputs/flutter-apk/app-release.apk`. Obtain the passing final-candidate artifact and record the PR head, actual checkout/merge SHA, run ID, APK hash and signature. The current workflow uploads the release variant only; debug signing does not make it debuggable. Private-file inspection and controlled failure need a separate debuggable diagnostic candidate and remain UNRUN without one.

Implementation/context: [scanner percentage review](cellar-label-percentage-token-review-2026-09-30.md), [current acceptance plan](remaining-companion-acceptance-2026-09-30.md), [Android build workflow](../../.github/workflows/ci.yml). Android results are pending; iPhone unavailability does not become an iOS pass.

## Measured CI artifact availability: 30 September 2026 continuation

The completed Android log for [run 36708753882](https://github.com/Xaiando/Mobile/actions/runs/36708753882) records synthetic merge checkout **`39bc6159d6f51b59332c0a8fc1fa9f2d1eea5bea`**, corresponding to PR 45 head **`42bcb6f997c7df69a9ed5cba1c0af7130729fb46`**. Checkout identity is separate from the branch head.

| Artifact evidence | Recorded value |
| --- | --- |
| Name / ID | `sommelier-android-apk` / `11093148731` |
| Reported archive digest | SHA-256 `40a9755038fa0e45fd3d496d50b3c3f9538e1002366a0d17765ad4b54a897389` |
| Downloaded APK | `C:/Users/Kaged/.codex/worktrees/companion-acceptance-next/Sommelier study companion/build/ci-pr45-android-apk/app-release.apk` |
| Downloaded APK SHA-256 | `490F8AAC54D55AF501BC39F1C3A745D8219C2F41C612F53193886F6368D76E1C` |
| Device | Samsung Galaxy S22 Ultra, user-reported; Android/One UI version and API pending |
| Installation / signature verification | Neither observed |

The [artifact record](https://github.com/Xaiando/Mobile/actions/runs/36708753882/artifacts/11093148731) and extracted file establish an **available Android build**, not a final accepted release. The reported archive digest and separately hashed APK identify different objects and must not be substituted for one another.

Native CI remains pending and hosted Windows/web jobs failed at this continuation. Passing Android build/job evidence does not establish whole-workflow or release acceptance. No installation, signature verification or phone scanner behavior was observed. **All 12 device checklist rows remain UNRUN**, including offline OCR, permission/cancel, activity reclamation, failed-save retry, backup/restore and private-file cleanup. The prior USB observation and local Android SDK limitations remain unchanged.

The bounded next device action depends on the already-pending phone/version response and an identified acceptable candidate: record installed APK identity and signature/install outcome, then timestamp the checklist using disposable entries. Do not ask the same pending phone question again or treat artifact availability as camera/OCR/cleanup evidence. A release APK alone still provides no debuggable private-file or fault-injection evidence.

## Read-only device availability observation, 30 September

At approximately 13:44 UTC, the existing official Platform Tools `adb devices -l` command returned no connected Android device. No device serial was printed, no app was installed, and no operating-system settings or device data were changed. The user-specified model remains Samsung Galaxy S22 Ultra; Android/One UI version is still unconfirmed. Every physical acceptance row remains unrun. A future session must use the fixed accepted APK identity, not treat this availability check or the PR45 build as scanner acceptance.


## Subsequent CI conclusion and device reply

The original PR45 native job subsequently completed successfully with 1,395 passing tests at 14:12:11 UTC; its earlier pending status above is a historical observation. Existing Windows/web job failures and APK provenance remain unchanged. The user again identified the phone as Samsung Galaxy S22 Ultra; no Android/One UI version, installation or physical checklist outcome was supplied. All 12 rows remain UNRUN, and the PR45 APK still predates the separate CMS/D2/French continuation. Do not infer camera/OCR acceptance or repeat the pending version question from artifact availability.


The read-only Android inventory at 17:28:27 UTC on 30 September 2026 found zero connected devices. The user subsequently supplied Android 16 / One UI 8 as the phone version. This updates the planned test target only; every physical checklist row remains UNRUN, and no install, phone setting or user-data change was performed. The older PR45 APK provenance remains separate from the unpublished continuation.
