# СЭЛФИ ШИНОСНОМА — document selfie app for Tajikistan

A Flutter app (Android and iPhone) that turns a selfie into a ready document photo for Tajikistan:
passport, ID card, documents and certificates. Everything runs **on the phone, offline**: no server,
no Google Play services, works on cheap Android phones (including Huawei and other phones without Google).

Languages: Tajik (default), Russian, English.

## What works today

| Area | Status |
|---|---|
| Camera | Front/back, timer (3/5/10 s), night boost, screen light |
| Live face guide | Oval turns green only when one face fits it; hints: closer / farther / centre |
| Photo checks | Rejects closed eyes, turned or tilted head, smile/open mouth, no face, more than one person — right after capture |
| Photo fixing | White balance, exposure, side-shadow balance, red-eye, background replaced (white/grey/blue) |
| Document sizes | 3,5×4,5 (passport, ID), 3×4 (documents), 4×6 (certificates); head share per the 35×45 rule |
| Suits | **Switched off for launch** — people keep their own clothes (camera tip: dark shirt/jacket; warning when clothes match the background). Suit code kept (`kSuits` in `lib/flavor.dart`); planned later as an online feature |
| Export | JPEG / PNG / PDF at 300–600 DPI with real DPI tags; single photo, 10-photo sheet, A4 sheet; save to Pictures + Download, share, print |
| Payment | Monthly 10 смн or lifetime 50 смн, paid to the owner's Alif wallet. The owner checks the payment, then the owner app makes an 8-digit activation code (tied to the customer's phone number and plan) and sends it by SMS; the customer enters it and the app unlocks. Fully offline — no server (`lib/unlock_code.dart`) |
| Privacy | No internet permission, no analytics; photos never leave the phone; optional 7-day auto-delete |
| App size | ~22 MB (64-bit Android only) |

## Where help is needed: realistic suit replacement

The goal: the customer's own clothes disappear and a suit appears that looks like a real studio passport photo —
natural neck and collar, correct shoulders, no visible edges — **without changing the face or the neck**,
automatically (no manual adjusting by the customer), on the phone, offline.

Current approach (`app/lib/processing.dart`, function `_process`, section `--- suit`):

1. Face landmarks (468 points) give the face outline, jaw and chin; a person mask separates the person from the background.
2. **Clothing line:** going down the neck centre, the first row that no longer matches the neck's skin.
3. **Clothing removed:** below that line, and beside the jaw/neck, everything becomes background. Face and neck are protected.
4. **Measurements:** neck edges (skin scan, checked against the jaw width), shoulder line and width (person-mask outline).
5. **Suit warped onto the person:** collar opening scaled to the neck; collar-to-shoulder stretch set so the suit's shoulders
   land on the person's; jacket beyond the collar stretched to the body width.

Known weaknesses:

- Suit layers are cut from AI-generated photos (350×450 px) and enlarged ~4× → soft fabric, slightly stepped edges.
- The shirt area inside the collar is a plain white fill (`tools/fix_men_suits.py`), flat up close.
- Women's suits still have deep necklines and rough edges.
- Measurements come from simple colour/mask rules; dark or patterned clothes, hair on the shoulders, and close-up selfies are hard cases.

Constraints for any solution: runs on the phone (no server, no photo leaves the phone), no Google Play services,
reasonable speed on low-end Android, app size kept small.

## Project layout

```
app/                       Flutter app
  lib/
    main.dart              app start, licences
    app_state.dart         app state: photos, size, background, suit, plan, settings
    processing.dart        photo pipeline: analysis, checks, light/background fix, framing, clothing removal, suit fitting
    nn/runner.dart         our own small neural-network runner (pure Dart)
    nn/vision.dart         face detector, 468-point face mesh, person mask (MediaPipe models, Apache 2.0)
    live_face.dart         live face guide on camera frames
    export.dart            JPEG/PNG/PDF, sheets, DPI, save/share/print
    l10n.dart, l10n_more.dart   texts in Tajik / Russian / English
    theme.dart             colours and neumorphic styles
    screens/               splash, home, camera, settings, payment, legal
    widgets/               painters (logo, knob…), photo cards, rework animation, UI pieces
  assets/
    models/                face_detect.nnm, face_mesh.nnm, person_mask.nnm (converted MediaPipe models)
    suits/                 suit layers (PNG) + anchors.json (chin, neck, shoulder, throat, collar opening per suit)
    samples/               example photos for the demo list
    banks/                 bank / e-wallet logos
  test/                    automatic checks (pipeline, suit fit, live face, camera layout on 243 screen combinations…)

tools/
  convert_tflite.py        converts MediaPipe .tflite models to the app's .nnm format
  fix_men_suits.py         repairs men's suit layers (closed collars, ties, collar opening)
  clean_women_suits.py     removes leftover hair/backdrop bits from women's suit layers
  suit_prompts.md          prompts for generating new "invisible mannequin" suit pictures
```

## Build and run

Requirements: Flutter 3.47+ (Dart 3.13+), Android SDK 36, Java 17.

Two apps are built from the same code (64-bit Android only):

| App | For | Contains |
|---|---|---|
| **Сэлфи Шиноснома** (`customer`) | customers, Google Play | plans and activation code; only the camera permission |
| **Шиноснома · Соҳиб** (`owner`) | the owner's phone only, never published | always free (no plans, payment or watermark); confirms payments: makes the activation code and sends it by SMS |

```bash
cd app
flutter pub get
flutter analyze
flutter test                      # all checks; the suit generator runs only with MAKE_SUITS=1
# customer app (both apps MUST use the same secrets.json — it holds the activation-code key and is not in git)
flutter build apk --release --flavor customer --dart-define-from-file=secrets.json --target-platform android-arm64 --obfuscate --split-debug-info=build/symbols
# owner app
flutter build apk --release --flavor owner --dart-define=OWNER_APP=true --dart-define-from-file=secrets.json --target-platform android-arm64 --obfuscate --split-debug-info=build/symbols-owner
```

The APKs appear in `app/build/app/outputs/flutter-apk/` (`app-customer-release.apk`, `app-owner-release.apk`).

Regenerating suit layers (only when changing the source suit photos):

```bash
cd app && MAKE_SUITS=1 flutter test test/make_suits_test.dart
cd .. && python tools/clean_women_suits.py && python tools/fix_men_suits.py
```

## Not done yet

- `app/secrets.json` (activation-code key) exists only on the owner's computer: back it up. A new key makes all earlier codes invalid.
- iPhone build (needs a Mac or a cloud build service such as Codemagic) and store signing keys.
- Document scanner (removed for now).

## Licences

The face and person models are MediaPipe models by Google, Apache License 2.0 (credited in the app's licence list).
Bank and e-wallet logos belong to their owners and are shown only to identify the payment method.
