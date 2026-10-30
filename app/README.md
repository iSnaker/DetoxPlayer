# DetoxPlayer Flutter app

## Run locally

For USB testing on Android, forward the API port from the phone to the computer:

```powershell
adb reverse tcp:8081 tcp:8081
```

Create `test_defaults.local.json` in this directory with local-only test values:

```json
{
  "DETOX_TEST_SERVER_URL": "http://127.0.0.1:8081",
  "DETOX_TEST_DEVICE_KEY": "your-device-key"
}
```

This file is excluded by `.gitignore`. Run the app from this directory:

```powershell
flutter run -d <device-id> --dart-define-from-file=test_defaults.local.json
```

The connection screen uses these values as debug defaults. Without the local
define file, it pre-fills only the local server URL and leaves the key empty.
Do not use a test key in release builds; revoke it after testing if it is no
longer needed.

## Device verification status (Android PRA-TL10)

### Run command
```
flutter build apk --debug --dart-define-from-file=test_defaults.local.json
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r build\app\outputs\flutter-apk\app-debug.apk
```

| Check | Status |
| --- | --- |
| Connect over public HTTPS, catalog, search, playback, seek | verified |
| Background playback, notification, lock-screen controls | verified |
| Headset button control | not yet verified |
| Battery-optimization behaviour (Huawei kills background services) | not yet verified |
| Queue (current and upcoming tracks only), shuffle, repeat, restore after restart | queue, shuffle, repeat verified; restore after restart fixed, re-check by user |
| Local library cache (whole list in memory, refresh button), windowed queue, shuffle over the whole library | implemented, to be verified by user |
| Sections (Tracks, Albums, Artists, Playlists, Settings), add to queue, albums grid | implemented, to be verified by user |

## Offline, playlists and diagnostics (29 October 2026)

Implemented local playlists and native background downloads for Android/iOS.
Use the track menu or the album action buttons. Downloads and diagnostic export
are in Settings. Playback prefers verified local files and can reload a failed
source using Retry, preserving position. Playlists/downloads are scoped to the
server and device; cloud sync is not implemented.

Validation: `flutter analyze --no-pub` clean, `flutter test --no-pub` 33 passing
tests, Android debug APK built without embedded test credentials. Native iOS
build and background behavior on real phones remain unverified in this change.
See [device test scenarios and Mac steps](../docs/mobile-validation.md).

## Design and branding

The avocado theme, native icons, splash screens and compact/full player are documented in [design.md](../docs/design.md). Android application ID is now `com.snapix.detoxplayer`; this is a separate installation from the previous package.
