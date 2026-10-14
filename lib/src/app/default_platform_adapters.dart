import 'dart:io';
import '../android/android_media_controls.dart';

import '../data/drift/app_database.dart';
import '../diagnostics/diagnostics_service.dart';
import '../domain/repositories/repositories.dart';
import '../library/artwork_cache_service.dart';
import '../library/custom_artwork_service.dart';
import '../library/directory_picker_service.dart';
import '../library/metadata_reader_service.dart';
import '../player/just_audio_player_service.dart';
import '../player/player_service.dart';
import '../player/transition_player_service.dart';
import '../player/windows_playback_cache.dart';
import '../queue/playback_queue_service.dart';
import '../smtc/macos_now_playing_client.dart';
import '../smtc/smtc_service.dart';
import '../smtc/smtc_windows_plugin_client.dart';
import 'app_bootstrap.dart';
import 'resource_cleanup.dart';

enum AppHostPlatform { windows, macos, android, other }

AppHostPlatform detectAppHostPlatform() => Platform.isWindows
    ? AppHostPlatform.windows
    : Platform.isMacOS
        ? AppHostPlatform.macos
        : Platform.isAndroid
            ? AppHostPlatform.android
            : AppHostPlatform.other;

/// Native construction over one shared runtime; Android adds its media service.
final class DefaultAppPlatformAdapters implements AppPlatformAdapters {
  DefaultAppPlatformAdapters(
      {AppHostPlatform? platform,
      LocalAudioEngine Function()? audioEngineFactory})
      : platform = platform ?? detectAppHostPlatform(),
        _audioEngineFactory = audioEngineFactory;
  final AppHostPlatform platform;
  final LocalAudioEngine Function()? _audioEngineFactory;

  @override
  Future<AppDatabase> openDatabase(DiagnosticsService diagnostics) async =>
      AppDatabase.open(diagnostics: diagnostics);

  @override
  LocalLibraryAdapters createLocalLibrary() {
    final cache = AppSupportArtworkCacheService();
    return LocalLibraryAdapters(
        metadataReader: const AudioMetadataReaderService(),
        artworkCache: cache,
        directoryPicker: const FilePickerDirectoryPickerService(),
        customArtwork: FilePickerCustomArtworkService(artworkCache: cache));
  }

  @override
  Future<AppPlayerRuntime> createPlayer(
      AppRepositories repositories, DiagnosticsService diagnostics) async {
    final partial = <AppCleanupAction>[];
    LocalAudioEngine createEngine() =>
        _audioEngineFactory?.call() ??
        JustAudioEngine(
            handleInterruptions: platform != AppHostPlatform.android);
    try {
      final cache = WindowsPlaybackCache(diagnostics: diagnostics);
      final first = JustAudioPlayerService(
          playbackEvents: repositories.playbackEvents,
          settings: repositories.settings,
          diagnostics: diagnostics,
          playbackCache: cache,
          isWindows: platform == AppHostPlatform.windows,
          audioEngine: createEngine());
      partial.add(AppCleanupAction(AppResource.audioDeck, first.dispose));
      final second = JustAudioPlayerService(
          playbackEvents: repositories.playbackEvents,
          diagnostics: diagnostics,
          playbackCache: cache,
          isWindows: platform == AppHostPlatform.windows,
          audioEngine: createEngine());
      partial.add(AppCleanupAction(AppResource.audioDeck, second.dispose));
      final player = TransitionPlayerService(
          first: first, second: second, settings: repositories.settings);
      return AppPlayerRuntime(
          player: player, initialize: player.restoreSettings);
    } on Object catch (error, stack) {
      await closeAppResources(partial.reversed, diagnostics);
      Error.throwWithStackTrace(error, stack);
    }
  }

  @override
  SmtcService createMediaControls(PlayerService player,
          PlaybackQueueService queue, DiagnosticsService diagnostics) =>
      switch (platform) {
        AppHostPlatform.android => AndroidMediaControlsService(
            player: player, queue: queue, diagnostics: diagnostics),
        AppHostPlatform.windows => WindowsSmtcService(
            playerService: player,
            onNext: queue.next,
            onPrevious: queue.previous,
            client: SmtcWindowsPluginClient(),
            diagnostics: diagnostics),
        AppHostPlatform.macos => MacosNowPlayingService(
            playerService: player,
            onNext: queue.next,
            onPrevious: queue.previous,
            client: MacosNowPlayingClient(),
            diagnostics: diagnostics),
        _ => const NoopSmtcService(),
      };
}
