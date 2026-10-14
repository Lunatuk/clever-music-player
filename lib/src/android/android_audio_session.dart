import 'package:audio_session/audio_session.dart';

abstract interface class AndroidAudioSession {
  Future<void> configure();
  Stream<void> get interruptions;
  Stream<void> get becomingNoisy;
  Future<void> deactivate();
}

/// One interruption policy for the logical player, including both fade decks.
/// Playback resumes explicitly through Play; interruption endings never start it.
final class PluginAndroidAudioSession implements AndroidAudioSession {
  AudioSession? _session;
  @override
  Future<void> configure() async {
    final session = _session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music()
        .copyWith(androidWillPauseWhenDucked: true));
  }

  @override
  Stream<void> get interruptions => _session!.interruptionEventStream
      .where((event) => event.begin)
      .map((_) {});
  @override
  Stream<void> get becomingNoisy => _session!.becomingNoisyEventStream;
  @override
  Future<void> deactivate() async {
    await _session?.setActive(false);
  }
}
