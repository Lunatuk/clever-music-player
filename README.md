# Clever Music Player

Local-first Flutter smart music player architecture.

## Current scope

- Windows/macOS desktop first
- Android-compatible package structure
- Local Drift SQLite database
- Repository contracts with Drift implementations
- Recommendation service skeleton with score reasons
- Local recursive library scanning
- Fallback metadata extraction from file information
- Placeholder UI for folder scanning and track listing

Audio playback and sync are intentionally not implemented yet.

## Development

Generate Drift code after installing Flutter dependencies:

```sh
flutter pub get
dart run build_runner build
flutter analyze
flutter test
```
