# Mail

A native Flutter Android email client for real Gmail accounts.

## Implemented

- Gmail OAuth authentication using Google Sign-In.
- Gmail API mailbox synchronization.
- Multiple account entries and account switching UI.
- Server-side message deletion through Gmail's API.
- Message text selection and copy through Flutter's native selection controls.
- Pure black and white themes.
- Arabic/English UI selection.
- Notification preference storage.
- `arm64-v8a` release APK CI build.

## Google configuration

The app uses Google's OAuth flow rather than storing Gmail passwords. Flutter's Google API guidance recommends Google authentication for end-user Gmail data. The app requests `https://mail.google.com/` because the requested delete behavior is permanent server-side deletion; Google classifies this as a restricted Gmail scope. A Google Cloud project, Gmail API enablement, OAuth consent configuration, and an Android OAuth client matching the final package/signing configuration are required for real account sign-in. See Google's Gmail OAuth scope documentation before distributing the app.

The repository intentionally contains no OAuth client secret, keystore, or `google-services.json`.

## Build

The GitHub Actions workflow runs `flutter analyze`, `flutter test`, and builds only `android-arm64` before uploading the APK artifact.

## Important

Server synchronization is authoritative: message IDs come from Gmail and delete operations call Gmail's server API. The app does not use a fake local mailbox.
