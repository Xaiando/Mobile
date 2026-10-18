# Online label reader

The wine editor reads a label in two ways. The phone's own reading (Google ML
Kit, offline) runs on every label photo and works with no network. The
optional online reader sends the photos to Anthropic's Messages API and gets
back the producer, cuvée, appellation, grapes, vintage and alcohol level that
are printed on the label. Either way the result is a set of clues: the learner
taps each one to use it, and nothing is filled in by itself.

This is the app's one network feature. It exists because label reading by
photo is only as good as what does the reading: Vivino's accuracy comes from
a server that matches the photo against millions of label pictures, which this
app cannot hold or license, and a vision model reads the print directly with
no database. The decision is the owner's (2026-10-18); the earlier plan was an
offline-only improvement.

## What the learner sees

* **Settings > Label reading** (Android only): paste an Anthropic API key and
  switch the reader on. The key is the learner's own, so their Anthropic
  account is billed for each reading.
* **Wine editor > Scan label** (or Choose label) takes the front. **Add back
  label** and **Add another photo** add up to four photos of the same bottle,
  each read by the phone as well. This is also the fallback when there is no
  key, no network or the service fails: the phone's reading of every photo is
  combined in the text box.
* **Read with online AI** sends the photos. The first time, a notice says that
  the photos go to Anthropic with the learner's key and are billed to them;
  nothing is sent before the learner agrees, and nothing is ever sent except
  by that button.
* Every failure says what happened (no connection, key refused, service busy,
  photos too large, unusable answer) and leaves the phone's clues in place.

## What goes out, and what stays

* Only the label photos in the scan, re-encoded as JPEG, at most 1,568 px on
  the longest side, with the camera's metadata (location included) removed. Only
  the first photo is saved in the journal; the others are dropped when the scan
  is replaced or the editor closes.
* One request to `https://api.anthropic.com/v1/messages`, with the key in the
  `x-api-key` header. The key is kept by Android's Keystore (AES-GCM,
  `SecretVault.kt`), never in the study database, so exports, review ZIPs and
  the Auto Backup exclude it (`backup_rules.xml`, `data_extraction_rules.xml`).
  It is never logged and no error message contains it.
* The model's answer is untrusted. It is forced into one tool call
  (`record_label`) and each field is cut to a short plain string or a number in
  range (`LabelAiResult.fromToolInput`), so text printed on a label cannot put
  instructions or odd values into the journal. The prompt tells the model to
  transcribe only what is printed and to leave a field out when it is not.

## Consequences to know

* The release APK now holds the INTERNET permission, which the earlier build
  removed on purpose. `tool/android/verify_apk.py` allows it, and a build that
  must stay offline can fail on it with `--forbid-permission`.
* With INTERNET present, Google's ML Kit text recognition may send usage and
  performance statistics to Google (its data disclosure). That was the reason
  the permission had been removed. The Settings text says so.
* `docs/legal-review.md` L-32 records what has to be decided before a store
  release: privacy labels, the README's "everything runs offline", and
  Anthropic's terms for an app that relays photos.
* The emulators cannot call the service (there is no key in CI). They show that
  the key vault works under R8 and that the app still passes its checks; only
  the phone with a key shows how well the reading works.

## Changing it

* The model is `LabelAiClient.defaultModel`. A cheaper model reads less well.
* The prompt and the tool schema are in `label_ai_client.dart`.
* Tests: `test/core/label_ai/` (parsing, request, errors, key rules) and
  `test/features/journal_scan_online_test.dart` (front and back photos, the
  notice, failure, switched off, Settings).
