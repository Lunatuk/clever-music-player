# flutter_secure_storage_windows 4.1.0

Source: [official pub.dev archive](https://pub.dev/api/archives/flutter_secure_storage_windows-4.1.0.tar.gz).
Archive SHA-256: `3b7c8e068875dfd46719ff57c90d8c459c87f2302ed6b00ff006b3c9fcad1613`.
MIT license retained. This application-scoped fork is not a general replacement for upstream.

Local changes:
- Bounded IO errors instead of unlimited retries; do not erase unreadable/corrupt ciphertext or log raw errors.
- Atomic ciphertext-only temp/flush/MoveFileEx replacement; preserve the old file on commit failure.
- Native cryptography remains Windows DPAPI with CRYPTPROTECT_UI_FORBIDDEN.
- Remove the unused pre-4.x C++ credential/AES migration implementation and its ATL dependency.
  The retained registrar/channel explicitly returns NotImplemented for legacy calls.
  The application always passes useBackwardCompatibility=false and uses the Dart DPAPI backend;
  no legacy credential migration or legacy data access is supported by this private fork.

See [application contract](../../docs/architecture/yandex-account-settings.md).
