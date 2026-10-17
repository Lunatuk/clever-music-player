# Clever Music Player

Local-first Flutter smart music player architecture.

## Current scope

- Windows/macOS desktop first
- Android-compatible package structure
- Local Drift SQLite database
- Repository contracts with Drift implementations
- Recommendation service skeleton with score reasons
- Local recursive library scanning
- Exact file copies are hidden in My Music and Wave using full-file SHA-256;
  same-title tracks with different bytes remain separate
- Fallback metadata extraction from file information
- Placeholder UI for folder scanning and track listing
- Playback queue is session-local in v1 and is not persisted across restarts
- Smart Wave prepares the next candidate in advance; recommendation debug explains the selected track
- Silent next-track preloading and automatic crossfade (default 3 seconds, configurable 0–10)

Server sync is intentionally not implemented yet.

## Reliability work

See the [roadmap](docs/ROADMAP.md), [implementation log](docs/IMPLEMENTATION_LOG.md)
and [targeted manual checks](docs/MANUAL_CHECKS.md) for completed changes,
verification results and remaining work.

Package 24 introduces provider IDs with optional album/version context, provenance
and exact, indexed lookup. Several independent local copies can share an external
ID; matching names never creates associations. Bounded writes are atomic and
idempotent. Existing records and user data survive migration from schemas 1-9.
This is groundwork for Yandex synchronization; account access and downloading
are subsequent work. See [identity rules](docs/architecture/external-track-identities.md).

Package 25 records completed publications, their actual format/quality and file
verification evidence separately from external identities. Replays are idempotent;
snapshot checks reject stale operations. Candidate reuse respects the destination,
source, known file properties and availability, and still requires a current OS/file
check. No existing music is marked as a verified download during migration.
See [downloaded asset rules](docs/architecture/downloaded-assets.md).

Package 26 adds account configuration without credentials, collection selection
and atomic ordered remote snapshots. Partial or stale responses cannot replace
the last successful content. Provider likes remain separate from local feedback;
network login and downloads follow later. See [snapshot rules](docs/architecture/remote-library-snapshots.md).

Package 27 adds a durable deduplicated job queue, finite attempts, leases and
reconciliation checkpoints. Session/folder changes revoke stale work atomically;
completion requires current downloaded-asset evidence. The physical downloader
and coordinator are still subsequent work. See [job rules](docs/architecture/durable-download-jobs.md).

Package 28 adds deterministic update planning across selected collections, exact
resource candidates and existing jobs. Atomic application rechecks the full input,
keeps retry budgets and cancels obsolete pending work within the destination.
Candidate files still need physical checks; no network/UI integration yet.
See [planning rules](docs/architecture/library-sync-planner.md).

Package 29 adds physical reuse checks for registered resources: full-file SHA-256
and size on desktop and streaming SAF reads on Android. Missing, denied, changed
and transient failures remain distinct; revision checks reject stale results.
Cancellation drains reads and accepted writes before SQLite closes. Matching
bytes preserve previous audio-format evidence; this is not a decoder for new
downloads. The checker is lazy and internal; login/download UI follows later.
See [physical check rules](docs/architecture/downloaded-asset-byte-checks.md).

Package 30 adds read-only validation of completed staging audio: actual container,
codec/encoding policy, expected tags and duration, full audio/cover decode, and
stable SHA-256 before/after. Its desktop FFmpeg adapter uses explicit executable
paths, bounded child-process output and cancellation. Real synthetic MP3/M4A/FLAC
checks cover PNG/JPEG, corruption and truncation. Helper packaging and the Android
native backend remain subsequent work; ordinary playback does not run this module.
See [new audio validation rules](docs/architecture/downloaded-audio-validation.md).

Package 31 adds desktop staging, an immutable publication journal, OS resource
locks and publication that refuses to replace an existing file. SQLite reserves
its writer before checking the current lease/session/destination for a short
physical effect; hashing and decoding stay outside that transaction. Explicit
reconciliation verifies the final bytes after interrupted publication. A small
bundled C asset captures OS errors before returning through Dart FFI. Import,
network access and UI integration still follow. See [publication rules](docs/architecture/desktop-file-publication.md).

Package 32 fixes far scrollbar jumps in large libraries: desktop and Android
measure one representative row and build only the destination viewport. Row
geometry follows text scaling; the measuring row reads no artwork. Regression
checks use 6000 synthetic tracks, mouse thumb dragging, enlarged text, filtering
and playback after a jump. See [scrolling limits and evidence](docs/architecture/large-library-scrolling.md).

Package 33 prepares downloaded audio tags and PNG/JPEG artwork in a separate
private file without audio transcoding. It verifies encoded packets, decoded
PCM, cover bytes and final file evidence before handing the result to the
publication pipeline. Cancellation drains work before cleanup. Track and album
artist roles are now separate in the shared tag reader. Helper bundling, native
Android preparation and the network coordinator/UI remain subsequent work.
See [metadata preparation rules](docs/architecture/downloaded-audio-metadata.md).

Package 34 bundles a compact offline FFmpeg/ffprobe helper for Windows x64,
built from pinned sources with its DLLs, licenses and complete corresponding
source archives. Settings → Diagnostics can explicitly check integrity,
versions and required codecs; startup/playback do not run the helper. No
user-installed FFmpeg or Python is needed. Windows CI builds and qualifies the
actual bundle with synthetic audio. macOS helper packaging and native Android
preparation remain separate work; no new Android APK in this package.
See [bundle and qualification rules](docs/architecture/bundled-media-helper.md).

Package 35 connects prepared desktop audio, publication and atomic library import.
Track, provider identity, downloaded asset and job completion commit together;
lost acknowledgement replays retain manual metadata and listening history.
A serialized lease heartbeat stays current during file work. Recovery checks
published bytes and can finish an interrupted import after reopening SQLite,
without downloading again. Real MP3/M4A/FLAC coordinator checks run with the
qualified Windows helper. Transport and Yandex login/update UI still
follow. See [coordinator and import rules](docs/architecture/download-publication-coordinator.md).

Package 36 adds bounded publication staging and journal maintenance. A folder
OS lock serializes reservations (512 operations / 16 GiB reserved staging by
default); completed music does not consume the staging quota. Before each
coordinated operation, cleanup checks current terminal jobs and matching assets
under a SQLite writer fence. Imported journal entries can be removed after
checking the final bytes; failed/cancelled staging waits at least 24 hours.
Unresolved results and unknown files are preserved. Durable retirement records
allow interrupted cleanup to resume, and remain readable by recovery. Final
music and persistent lock files are never deleted. No startup work or new UI
is enabled. See [retention rules and limits](docs/architecture/publication-retention.md).

Package 37 adds an independently implemented Dart reader for Yandex account
identity, the user's playlist catalog, liked tracks and selected playlist contents.
It uses four read endpoints at a fixed HTTPS origin, rejects redirects, bounds
responses/time/pages and cancels/drains active HTTP. Complete collections are
observed twice, with owner/count/revision/order checks and explicit paging.
The refresher commits through the existing revisioned snapshot repository;
errors, deselection and account changes preserve the previous mirror. Tests use
synthetic HTTP and temporary SQLite, including the existing durable planner.
No account login, credential persistence, download transport or new UI is enabled
yet; a real authorized account check follows the login step. See
[protocol, completeness and limits](docs/architecture/yandex-library-adapter.md).

Database schema v13 preserves existing track IDs and history. Metadata signatures
are non-unique, feedback changes preserve listening counters, and playback events
and their counters commit together. Retrying an event's operation ID does not
count it twice. Keep a consistent SQLite backup before upgrading; use a
compatible backup when returning to an older app version.

Desktop CI checks formatting, analysis, tests and release builds on Windows
and macOS with Flutter 3.41.9. The optional real-library migration test is
documented in the implementation log and always uses a temporary copy.

## Application assembly

`bootstrapApplication` builds the shared player, queue and library controller
through `AppPlatformAdapters`; `main.dart` only starts the application and installs
diagnostics. Current native construction lives in `DefaultAppPlatformAdapters`.
Startup failures release already acquired resources and preserve the original
error. Dependency disposal shares one completion future and attempts later
resources even if an earlier cleanup fails. System media disposal waits for
initialization and active commands/state writes before closing the native client.

Player and queue disposal reject new work, drain accepted history/feedback/settings
writes, and stop selection reads after shutdown. Media, queue and player shutdown
start together so native disposal can interrupt a command waiting for a decoder;
SQLite stays open until all owners settle. Both decoders and public streams are
attempted even after a native cleanup failure. Native Play waits are cancelled
without waiting for the recording to end; late results cannot restart database
work. Native window-close interception is still a separate host integration.

See [ownership and remaining lifecycle limits](docs/architecture/application-bootstrap-and-lifecycle.md).
Android now has a small SAF document prototype using the same runtime. The first
target device is a Xiaomi Redmi Note 14 Pro (8/512 GB, Android 16). Packages 18
and 19 were manually verified; Android background playback and media controls
work on that phone. Package 20 folder import was also verified; package 21 saved
folders await their targeted device checks.

## Audio source references

`Track.source` exposes a typed `FileAudioSource` or `ContentUriAudioSource`;
`Track.fromSource` and `copyWith(source: ...)` keep the existing storage and IDs.
Schema v9 retains literal desktop paths or the original content URI in the legacy
`file_path` column. URI identity is never lowercased or filesystem-normalized.

The player passes content URIs through `LocalAudioEngine.setSource` without
File.exists/stat or the Windows playback cache. Installed just_audio receives a
progressive URI on Android; desktop rejects content before native loading. The
existing preload, crossfade, cancellation and queue logic is shared. The scanner
still reads regular files. Android SAF grants and native metadata/cover reading
are available in the prototype; URI hashing and bulk library import remain
separate work. Background audio uses the existing shared runtime.
See [the source reference contract](docs/architecture/audio-source-references.md).

## Android preview (package 28)

`dist/clever-music-player-core-28-android-arm64.apk` updates **Clever Music Preview**
in its own Android sandbox. The compact screen selects up to 64 audio documents
at a time through the system picker, stores read-only persistent grants and uses
the shared database/player/queue. Re-selecting the same URI keeps the existing
record and manual edits. Audio files are not copied into app storage.

Folder import traverses subfolders in bounded pages and supports cancellation.
Selected folders refresh without the picker; package 20 tree grants bootstrap
the initial list. Package 22 links Android tracks to the shared folder model:
removing a folder hides its tracks, and adding it again restores their IDs and
user data. Existing tree documents are adopted without rescanning, including
folders forgotten in package 21. Separate document imports remain independent.
The Folders screen also checks and restores access. Files and grants are retained.
See [saved folder rules](docs/architecture/android-saved-folders.md).
Package 23 applies the desktop filename/tag metadata rules to Android imports.
Useful tags take priority; SAF display names fill missing artist/title, without
parsing opaque URIs. Refresh updates existing automatic records and preserves
manual edits, identity and user data. See [metadata rules](docs/architecture/android-audio-metadata.md).
Different provider URIs of one physical file still need a future
identity/alias layer; see [folder import limits](docs/architecture/android-folder-import.md).

Playback continues in the background using audio_service and the same player,
queue and Wave history. Notification/lock-screen/headset commands control this
runtime. Audio interruptions and headphone removal pause both crossfade decks;
resume explicitly with Play. Stop ends playback and removes the notification.
This is a debug-signed release-mode prototype, not the final design or store release.
Package 28 also provides `dist/clever-music-player-core-28-windows-x64.zip`.
Both platforms use schema 13 with external identities, downloaded asset evidence,
remote account/collection snapshots and durable download jobs.
See [targeted checks](docs/MANUAL_CHECKS.md)
and [background playback contract](docs/architecture/android-background-playback.md).

## Wave navigation

Finishing a library/playlist still continues with Wave. The queue keeps a
session-only timeline of six track references, allowing five previous visits.
The first Wave visit can return to the last track of the finished list. Forward
navigation retraces played visits before asking Wave for a fresh recommendation;
manual queued items retain priority. Explicit list/single/queued playback starts
a new timeline. After five seconds, Previous restarts the current track first,
as before; a second press returns to history. No audio buffers or database schema
changes are involved. See [history rules and tests](docs/architecture/wave-history.md).

## Playback transitions

The next track opens in a second silent decoder while the current track plays.
Automatic transitions can overlap their audio; manual selections switch directly.
Settings → «Переходы между треками» controls the overlap (0 disables it while
keeping preloading). Volume, mute and pause apply to both outputs. Seeking or
manually choosing a track cancels the outgoing tail. Preloading does not count as
listening, and both open Windows cache files are protected from cleanup.

This reduces source preparation at the boundary; sample-accurate gapless playback
has not been measured on real hardware. Unknown native duration and unsuccessful
preloading use the regular end-of-track path. Android/macOS audio validation remains
part of their platform stages.

## Unavailable files and playback cache

Automatic playback bypasses unavailable/failed sources with a 20-attempt bound;
explicit selections report the failure. Manual selection, pause and stop cancel
recovery. Failures of transport/volume controls do not trigger source recovery.

Windows cache copies are staged, checked against the source size/modification time,
flushed, and renamed into place. Open decoder files remain protected. The 250 MiB
retention target may be exceeded temporarily by active/prepared large recordings;
cleanup runs when their decoder references are released. Source files are unchanged.

## Exact copies in the library

Scanning computes full-file SHA-256 in a worker isolate with streamed reads.
Rescan existing folders once to detect copies imported by older versions.
Explicit rescans read bytes again, including files whose size/date are unchanged,
so scanning large collections takes longer. File stats are checked around hashing
and after metadata reads; failed checks leave the entry visible separately.

My Music hides verified exact copies by default. «Показывать точные копии» reveals
every record; searching by an alternate copy's path still finds it. Available
enabled-folder entries take precedence over missing entries. The original imported
ID is preferred otherwise. The toggle lasts for the current app session.

Each copy keeps its ID, edits, feedback, history and playlist memberships. Feedback
is still per record; a different representative can show different saved feedback.
Existing playlists and explicit queues retain their selected entries. Wave omits
exact copies without changing its scoring rules. No source files are removed.
Different encodings or files with different embedded tags/covers remain separate;
recognizing the same recording across such files is outside this exact-copy check.

## Scan progress and stopping

Home/Settings show the current folder, completed-file counters and processing
stage during scanning. The progress bar is for the current file's hash when its
size is known; total library size is not pre-counted. Progress has its own UI
subscription, coalesced at 100 ms, independent of library-list rebuilding.

«Остановить сканирование» retains completed work and stops further folders. An
incomplete traversal does not mark unseen tracks missing or advance the folder's
last complete-scan timestamp. Retry scans from the beginning without creating
duplicate path records. Completed folders in a bulk operation keep their results.

Hash workers stop cooperatively between bounded reads (up to 256 KiB) and close their file before
returning. An already started OS read, metadata operation or database write must
finish, so stopping may take time on slow/unavailable storage. Commands remain
reserved until cleanup is done. Shutdown requests cancellation and drains work
before SQLite closes. This is not a persisted resume cursor or a rollback of the
whole scan. Source files remain unchanged.

## Import performance

Windows hashes use system CNG SHA-256 with a portable Dart fallback. They produce
the same full-file/content-cache keys; duplicate detection still reads and checks
all bytes. Tag parsing runs in a worker isolate, and artwork lookup probes the
known content-addressed filenames instead of enumerating the cache directory.
The local `audio_metadata_reader` override guarantees reader cleanup on failed
format/picture parsing; its source snapshot and license are in `third_party`.

Prepared scan records are saved in short atomic batches (up to 64), including a
final flush on cancellation. Latest manual tags and custom covers survive
concurrent imports; files are rechecked before committing buffered identities.
The indexed-file counter uses COUNT instead of a second full metadata list.
Each folder scan owns one lazy sequential hash worker and drains it before
returning. ReadInto reuses a bounded buffer within each file; SHA-256 keys stay
compatible. Concurrent worker requests are rejected instead of queued.

Scan progress/results include time, files/s and verified MiB/s. Local diagnostics
include aggregate hash/tag/artwork/database timings in microseconds, verified
bytes/files, native-hash count and tag-read count, without paths or tags. Timings
include awaits and worker startup. Detailed hash IO/digester/worker/transport
and database lookup/import/maintenance fields are nested within the aggregate
phases, not additional independent totals. Remaining delays stay in elapsed.

Reproduce synthetic operation benchmarks (fresh temporary data, likely warm OS
cache; not full-library throughput):

```sh
dart compile exe tool/benchmark_file_hash.dart -o <output-path>
dart compile exe tool/benchmark_hash_worker.dart -o <worker-benchmark-output>
# Run the resulting executable.
flutter test --no-pub tool/benchmark_artwork_cache_test.dart --reporter expanded
flutter test --no-pub tool/benchmark_import_database_test.dart --reporter expanded
```

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


## Local diagnostics

Settings → «Диагностика» creates a local JSON report and opens its folder.
Release builds retain structured startup, database/migration, scan, audio-load,
cache and system-media outcomes. Only fixed event names, numeric/boolean fields
and fixed exception categories are accepted: paths, titles, artists, URLs,
exception messages and stack traces are excluded. Export validates stored fields
again and skips damaged journal lines; it does not include the library database.
Nothing is sent automatically.

The journal retains four files of up to 256 KiB and three reports. Writes are
asynchronous with a 128-record queue; I/O failures and overflow drop diagnostic
events instead of stopping playback. The report includes the dropped-record
count for the current session. An OS lock and in-isolate serialization coordinate
journal access; a busy lock does not block playback. Reports are published after
writing and flushing a temporary file. Release export, folder opening and persistence across app launches were
confirmed by the user and two release reports on 13 October 2026.


## Playback UI and Windows first play

The bottom player, volume control, queue panel and feedback button now live in
separate UI components and keep using the existing shared player/queue services.
See [the architecture note](docs/architecture/playback-ui-and-windows-transport.md).

The vendored Windows adapter reports native processing state separately from
just_audio's requested `playing` state. This prevents a late preparation event
from cancelling the first play during audio-session activation. The regression
uses the installed just_audio library and its method/event channels. On Windows,
run `./tool/check_windows_audio_contract.ps1 -FlutterRoot '<Flutter SDK path>'`
to compile the native payload builder and validate the checked-in protocol
fixture; Windows CI runs this before Flutter tests. Actual cold-start sound and
system media keys remain part of package 7's targeted manual checks.


Package 38 adds a lazy Yandex connection screen on Windows and Android: existing
OAuth token, OS-protected storage, likes/playlist selection and explicit collection
checks. SQLite session revisions bind the credential; stale logout cannot erase a
newer login. Windows secure storage is vendored to bound failures and atomically
replace ciphertext without deleting damaged data. Downloading follows next.
See [connection rules](docs/architecture/yandex-account-settings.md).

Package 39 adds an explicit credential-free API connection check and safe network
stage/timing/status diagnostics. Login shows account/playlist/storage steps and
network timeouts identify the failed phase. The reported real-account timeout is
still under investigation. See [network diagnostics](docs/architecture/yandex-network-diagnostics.md).

Package 40 saves the verified login before playlist discovery, combines own and
saved playlists using owner/kind identities, and tolerates optional catalogue
labels/counts without weakening complete-track snapshot checks. Discovery errors
can be retried with the saved credential. See [catalogue rules](docs/architecture/yandex-playlist-catalogue.md).

## Library operation ownership

One app-scoped `LibraryController` handles folder selection, scans, enable/disable
and confirmed source removal. It reserves the library before opening a picker;
competing commands return a busy result rather than running later. UI state
survives page/widget changes. App dependency disposal rejects new commands,
ignores late picker results and drains active database work before closing SQLite.
This is graceful disposal, not a promise to finish work after process termination.

Removing a disabled source checks its current database state and removes its
owned tracks, feedback/history and playlist memberships in one transaction.
A failure rolls everything back; an already removed source is a successful no-op.
Adapters without atomic removal support fail before changing rows. Source audio
files are preserved. This gate coordinates commands in the current app instance;
future download/background adapters must join the operation coordinator explicitly.
