abstract interface class SystemMediaControlsService {
  Future<void> initialize();

  Future<void> dispose();
}

final class NoopSystemMediaControlsService
    implements SystemMediaControlsService {
  const NoopSystemMediaControlsService();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}
}
