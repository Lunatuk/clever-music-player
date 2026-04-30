# Clever Music Player

Local-first Flutter smart music player architecture.

## Current scope

- Windows/macOS desktop first
- Android-compatible package structure
- Local Drift SQLite database
- Repository contracts with Drift implementations
- Recommendation service skeleton with score reasons
- Placeholder UI for architecture wiring

Audio playback, folder scanning, and sync are intentionally not implemented yet.

## Development

Generate Drift code after installing Flutter dependencies:

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```
