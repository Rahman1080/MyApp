# Phase 4 Report — Receipt Capture, OCR, and Attachments

**Date:** 2026-09-30
**Status:** Complete — tests green, analyzer clean, debug APK built with all native plugins compiling.

## What was built

### 1. Permission handling (rationales + graceful denial)
- `lib/core/permissions/permission_service.dart`
- Rationale dialogs appear **only when the user taps** a scan/photo action — never at app start.
- Handles granted / limited / denied / permanently-denied states; denied shows an explanatory snackbar, permanently-denied offers a one-tap shortcut to system Settings.
- All plugin `Permission` values mapped through one place (`PermissionService`), so the UI never touches `permission_handler` directly (testable seam).

### 2. Receipt capture service
- `lib/features/receipts/domain/receipt_capture_service.dart`
- `image_picker` for camera and gallery; on-device OCR via `google_mlkit_text_recognition` (Latin-script recognizer).
- `TextRecognizer` is injected (defaults to `TextRecognizer(script: TextRecognitionScript.latin)`), and `close()` disposes it — the scan screen owns disposal of the service it creates.

### 3. Pure-Dart OCR text parser (testable, no device needed)
- `lib/features/receipts/domain/receipt_text_parser.dart`
- Heuristics:
  - **Store:** first meaningful non-noise line.
  - **Date:** first valid date in `MM/DD/YYYY`, `MM-DD-YYYY`, `DD.MM.YYYY`, or `YYYY-MM-DD` (validated, not just pattern-matched).
  - **Total:** a line labeled `total`/`amount due`/`balance` wins; otherwise the largest currency-like amount; lines containing `subtotal`/`tax`/`vat`/`change`/`cash` are excluded. (Fixed a bug where the label regex matched "subtotal" as "total" — labels now use word boundaries.)
  - **Subtotal / tax:** extracted separately when labeled.
- Returns `ParsedReceipt(store, date, totalCents, subtotalCents, taxCents, rawText)`. All amounts in integer cents.

### 4. Scan flow UI (Confirm / Discard — never silent)
- `lib/features/receipts/presentation/receipt_scan_screen.dart` + `widgets/receipt_confirm_form.dart`
- Flow: pick source (camera/gallery) → permission rationale → OCR with progress indicator → **editable confirmation form** → explicit **Confirm** (saves) or **Discard** (deletes temp image).
- The form pre-fills store/date/total/subtotal/tax; the user can edit everything or leave fields blank for manual entry.
- The confirm form is a plain widget taking `parsed` + `onConfirm`/`onDiscard` callbacks — no plugin dependencies, fully widget-testable.

### 5. App-private file storage
- `lib/shared/services/file_storage.dart`
- Receipts → `<app-documents>/receipts/`, documents → `<app-documents>/documents/`, UUID-prefixed filenames, allow-listed extensions, `..` sequences collapsed, traversal-safe.
- Best-effort deletion; never throws on missing files.

### 6. Purchase detail integration
- `lib/features/receipts/presentation/widgets/receipt_section.dart` — thumbnail, full-image view dialog, delete-with-confirmation, "Scan receipt" entry point.
- `lib/features/documents/presentation/widgets/documents_section.dart` — attach any file, list name/size, inline image preview, info tile for non-images, delete-with-confirmation.
- `lib/features/documents/domain/document_service.dart` — `pickAndAttach` uses the new **file_picker 13 static API** (`FilePicker.pickFiles()` returning `List<PlatformFile>`), stores via `FileStorage`, records a `Document` row.
- Home "Scan receipt" quick action now opens a purchase picker that routes to `/scan?purchaseId=…` (replaces the Phase 3 placeholder).
- After returning from `/scan`, the receipt section reloads so the new receipt appears.

## Platform configuration

### Android (`android/app/src/main/AndroidManifest.xml`)
- `android.permission.CAMERA` — receipt scanning; requested at runtime only when the user taps scan.
- `android.permission.READ_MEDIA_IMAGES` — gallery picking on Android 13+.
- `android.permission.READ_EXTERNAL_STORAGE` with `android:maxSdkVersion="32"` — gallery picking on Android 12 and below.
- No broad storage permissions; `file_picker` uses the system picker.

### iOS (`ios/Runner/Info.plist`, validated with `plistlib`)
- `NSCameraUsageDescription`: honest description — photos stay on device, never uploaded.
- `NSPhotoLibraryUsageDescription`: honest description, same guarantee.
- **iOS deployment target raised 13.0 → 15.5** in `ios/Runner.xcodeproj/project.pbxproj` (all 3 build configs). Required: `google_mlkit_text_recognition` 0.16.0's podspec declares `s.platform = :ios, '15.5'`. Without this, `pod install` on macOS would fail. No `Podfile` exists yet (generated on first macOS build); it will inherit 15.5 from the project.

## iOS static review
- All four new plugins ship iOS implementations (`image_picker`, `google_mlkit_text_recognition`, `file_picker`, `permission_handler`).
- No Android-only Dart paths: no `Platform.isAndroid` branches, no `dart:io` Platform checks in the new feature code.
- Actual `flutter build ios` still requires macOS/Xcode — unchanged constraint.

## Dependency changes (final resolved versions)
| Plugin | Resolved | Note |
|---|---|---|
| `image_picker` | 1.2.3 | camera + gallery |
| `google_mlkit_text_recognition` | 0.16.0 | Latin-script on-device OCR |
| `file_picker` | 13.1.0 | **new static API** — `FilePicker.pickFiles()` → `List<PlatformFile>` (no `.platform`, no `FilePickerResult`) |
| `permission_handler` | 12.0.3 (android 13.0.1) | **downgraded from 13.0.2** — see below |

### Build incidents and fixes
1. **permission_handler 13.x broke the Android build.** `permission_handler_android` 14.1.0 ships a Kotlin-DSL `build.gradle.kts` requiring AGP 9.0.1 + Kotlin 2.3.20 + `compileSdk 37` — incompatible with this project's AGP 8.11.1 / Kotlin 2.2.20 / compileSdk 36. Downgraded to `permission_handler: ^12.0.1` (resolved 12.0.3 / android 13.0.1, classic Groovy script) and the build compiles. The Dart API used (`Permission.camera/photos/request/status/openAppSettings`) is unchanged across these versions. Revisit on a future AGP/Kotlin upgrade.
2. **Gradle build OOM-killed (exit 137).** A stale Gradle daemon from the first failed build held ~1.8 GB; ML Kit's native deps pushed the 7.8 GB sandbox over the edge. Killed the stale daemon, re-ran — incremental build completed in ~3.5 min.
3. **file_picker 13 API change** handled (see above).

## Tests
- `flutter test`: **133/133 passed** (112 existing + 12 OCR parser + 5 receipt-confirm widget + 4 file-storage).
  - New: `test/receipt_text_parser_test.dart` (12), `test/receipt_confirm_form_test.dart` (5), `test/file_storage_test.dart` (4).
  - Test fixes along the way: off-screen Confirm/Discard buttons needed `ensureVisible` (scrollable form); filename sanitizer now also collapses `..` sequences.
- `flutter analyze`: **No issues found.**

## Build verification
- `flutter build apk --debug` → **EXIT 0**, `✓ Built build/app/outputs/flutter-apk/app-debug.apk`
- Path: `~/workspace/keepit/build/app/outputs/flutter-apk/app-debug.apk` (~1.6 GB — debug + unstripped natives; known stub-NDK limitation, same as prior phases).
- APK contains `lib/arm64-v8a/libmlkit_google_ocr_pipeline.so` — proves the ML Kit native plugin compiled and linked.

## Known limitations / compromises
1. **One receipt per purchase.** The Drift schema declares `Receipts.purchaseId.unique()`. The UI is written as one-receipt-per-purchase to match; multi-receipt support needs a schema v2 migration (not done in this phase).
2. **Document preview is images-only.** Non-image files show an info tile (name/size/type); no external opener/share dependency was added — deliberate scope control.
3. **OCR is Latin-script only** (`TextRecognitionScript.latin`). Other scripts need a different recognizer instance.
4. **Debug APK is ~1.6 GB** — stub NDK means unstripped `.so` files (ML Kit's OCR libs are large). A real NDK is still required for production-sized APKs.
5. **iOS compilation unverified** — static review only; needs macOS/Xcode.

## Files added
- `lib/core/permissions/permission_service.dart`
- `lib/features/receipts/domain/receipt_text_parser.dart`
- `lib/features/receipts/domain/receipt_capture_service.dart`
- `lib/features/receipts/presentation/receipt_scan_screen.dart`
- `lib/features/receipts/presentation/widgets/receipt_confirm_form.dart`
- `lib/features/receipts/presentation/widgets/receipt_section.dart`
- `lib/features/documents/domain/document_service.dart`
- `lib/features/documents/presentation/widgets/documents_section.dart`
- `lib/shared/services/file_storage.dart`
- `test/receipt_text_parser_test.dart`
- `test/receipt_confirm_form_test.dart`
- `test/file_storage_test.dart`

## Files changed
- `pubspec.yaml` / `pubspec.lock` (4 new plugins)
- `lib/core/navigation/app_router.dart` (`/scan` route, database passed to detail)
- `lib/features/home/presentation/home_screen.dart` (purchase picker for scan)
- `lib/features/purchases/presentation/purchase_detail_screen.dart` (receipt + document sections, `database` param)
- `lib/core/database/repositories/document_repository.dart` (one-shot `getByPurchase`)
- `android/app/src/main/AndroidManifest.xml` (camera/media permissions)
- `ios/Runner/Info.plist` (camera/photo usage descriptions)
- `ios/Runner.xcodeproj/project.pbxproj` (deployment target 13.0 → 15.5)
- `test/receipt_confirm_form_test.dart` (ensureVisible fixes)
