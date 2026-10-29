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

| Check | Status |
| --- | --- |
| Connect over public HTTPS, catalog, search, playback, seek | verified |
| Background playback, notification, lock-screen controls | verified |
| Headset button control | not yet verified |
| Battery-optimization behaviour (Huawei kills background services) | not yet verified |
| Queue, shuffle, repeat, restore after restart | implemented, not yet verified on device |
