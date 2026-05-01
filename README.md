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
- Playback queue is session-local in v1 and is not persisted across restarts
- Smart Wave chooses the next track at transition time; recommendation debug explains the selected track

Server sync is intentionally not implemented yet.

## Development

Generate Drift code after installing Flutter dependencies:

```sh
flutter pub get
dart run build_runner build
flutter analyze
flutter test
```
