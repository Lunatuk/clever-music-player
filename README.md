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

Windows SMTC support uses `smtc_windows`, which builds through
`flutter_rust_bridge`/cargokit. Install `rustup` and make sure `rustup` and
`cargo` are available on PATH before building the Windows app. If cargokit
cannot find Flutter from a plain shell, set `FLUTTER_ROOT` to the Flutter SDK
directory. The cargokit build scripts are also sensitive to non-ASCII project
paths, so build from an ASCII-only checkout or junction path if the project is
under a localized folder name.

Windows builds intentionally use the local `third_party/just_audio_windows`
override. The patch disables the WinRT MediaPlayer's built-in system media
session so the app-owned `smtc_windows` session is the only source of Windows
media metadata and next/previous command handling.
