import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/async_lifecycle.dart';
import '../domain/models/track.dart';
import '../domain/repositories/repositories.dart';
import 'just_audio_player_service.dart';
import 'playback_transitions.dart';
import 'player_service.dart';
import 'player_state.dart';

/// Two independent decoders, exposed as one player to the UI and media controls.
/// The standby decoder is silent and never writes listening history until play.
final class TransitionPlayerService
    implements PlayerService, PlaybackTransitions {
  TransitionPlayerService({
    required JustAudioPlayerService first,
    required JustAudioPlayerService second,
    SettingsRepository? settings,
    @visibleForTesting Stopwatch? fadeClock,
  })  : _decks = [first, second],
        _active = first,
        _settings = settings,
        _fadeClock = fadeClock ?? Stopwatch() {
    for (final deck in _decks) {
      _subscriptions
          .add(deck.stateStream.listen((state) => _onDeckState(deck, state)));
    }
  }

  static const _crossfadeKey = 'player.crossfadeMilliseconds';
  static const maxCrossfadeDuration = Duration(seconds: 10);
  final List<JustAudioPlayerService> _decks;
  final SettingsRepository? _settings;
  final _states = StreamController<PlayerState>.broadcast();
  final _requests = StreamController<Track>.broadcast();
  final _settingsChanges = StreamController<Duration>.broadcast();
  final List<StreamSubscription<PlayerState>> _subscriptions = [];
  JustAudioPlayerService _active;
  JustAudioPlayerService? _outgoing;
  Track? _preparedTrack;
  Track? _desiredNext;
  int _preparationRevision = 0;
  int _commandRevision = 0;
  bool _disposed = false;
  final _operations = AsyncOperationTracker();
  Future<void>? _closing;
  bool _requestedTransition = false;
  bool _finishingFade = false;
  double _volume = 1;
  Duration _crossfadeDuration = const Duration(seconds: 3);
  Duration _fadeDuration = Duration.zero;
  final Stopwatch _fadeClock;
  Timer? _fadeTimer;
  Future<void>? _gainUpdate;
  PlayerState _state = const PlayerState.idle();

  JustAudioPlayerService get _standby =>
      identical(_active, _decks.first) ? _decks.last : _decks.first;

  @override
  PlayerState get state => _state;
  @override
  Track? get currentTrack => _state.currentTrack;
  @override
  bool get isPlaying => _state.isPlaying;
  @override
  Duration get position => _state.position;
  @override
  Duration? get duration => _state.duration;
  @override
  double get volume => _volume;
  @override
  Stream<PlayerState> get stateStream => _states.stream;
  @override
  Duration get crossfadeDuration => _crossfadeDuration;
  @override
  Stream<Duration> get crossfadeDurationStream => _settingsChanges.stream;
  @override
  Stream<Track> get automaticTransitionStream => _requests.stream;

  Future<void> restoreSettings() => _operations.run(() async {
        await _decks.first.restoreSavedVolume();
        if (_disposed) return;
        _volume = _decks.first.volume;
        await _decks.last.setVolume(_volume);
        if (_disposed) return;
        final value = await _settings?.readString(_crossfadeKey);
        if (_disposed) return;
        final milliseconds = int.tryParse(value ?? '');
        if (milliseconds != null &&
            milliseconds >= 0 &&
            milliseconds <= maxCrossfadeDuration.inMilliseconds) {
          _crossfadeDuration = Duration(milliseconds: milliseconds);
        }
        _publish();
      });

  @override
  Future<void> setCrossfadeDuration(Duration duration) =>
      _operations.run(() async {
        if (_disposed) return;
        final next = Duration(
            milliseconds: duration.inMilliseconds
                .clamp(0, maxCrossfadeDuration.inMilliseconds));
        await _settings?.writeString(
            _crossfadeKey, next.inMilliseconds.toString());
        if (_disposed) return;
        _crossfadeDuration = next;
        _settingsChanges.add(next);
        _requestedTransition = false;
        _maybeRequestTransition();
      });

  @override
  Future<void> prepareNextTrack(Track? track) => _operations.run(() async {
        if (_disposed) return;
        _desiredNext = track;
        if (_outgoing != null) {
          return; // Never open a third decoder during a fade.
        }
        if (track != null &&
            track == _preparedTrack &&
            !_standby.state.hasError) {
          return;
        }
        final revision = ++_preparationRevision;
        final deck = _standby;
        _preparedTrack = null;
        _requestedTransition = false;
        if (track == null) {
          // Cancellation must invalidate a pending load immediately, without
          // delaying foreground playback behind a slow disk/cache operation.
          unawaited(deck.stop());
          return;
        }
        try {
          await deck.setOutputGain(0);
          if (_disposed || revision != _preparationRevision) return;
          await deck.prepareTrack(track);
          if (_disposed ||
              revision != _preparationRevision ||
              deck.state.hasError ||
              deck.currentTrack != track ||
              deck.state.status != PlayerPlaybackStatus.paused) {
            return;
          }
          _preparedTrack = track;
          _maybeRequestTransition();
        } on Object {
          // A failed background preparation must leave the audible deck alone.
          if (!_disposed && revision == _preparationRevision) {
            _preparedTrack = null;
          }
        }
      });

  @override
  Future<void> playTrack(Track track) => _selectTrack(track, automatic: false);
  @override
  Future<void> playAutomatically(Track track) =>
      _selectTrack(track, automatic: true);

  Future<void> _selectTrack(Track track, {required bool automatic}) =>
      _operations.run(() async {
        if (_disposed) return;
        final revision = ++_commandRevision;
        final ready = track == _preparedTrack &&
            !_standby.state.hasError &&
            _standby.state.status == PlayerPlaybackStatus.paused;
        final remaining = _active.transitionRemaining;
        final incomingDuration = _standby.duration;
        var overlap = automatic &&
                ready &&
                _active.isPlaying &&
                remaining != null &&
                remaining > Duration.zero
            ? _crossfadeDuration
            : Duration.zero;
        if (remaining != null && overlap > remaining) overlap = remaining;
        // Short tracks still get an audible middle and cannot create cascading fades.
        if (incomingDuration != null && overlap > incomingDuration ~/ 2) {
          overlap = incomingDuration ~/ 2;
        }
        _cancelFade();
        _preparationRevision++;
        _preparedTrack = null;
        _desiredNext = null;
        _requestedTransition = false;
        if (ready) {
          final previous = _active;
          _active = _standby;
          if (overlap > Duration.zero) {
            _outgoing = previous;
            _fadeDuration = overlap;
          } else {
            unawaited(previous.stop());
          }
          // Publish the new logical track before the first await. The queue can
          // immediately prepare its successor without stopping this decoder.
          final gain = _active.setOutputGain(overlap > Duration.zero ? 0 : 1);
          final playing = _active.play();
          _publish();
          await Future.wait([gain, playing]);
          if (_disposed || revision != _commandRevision) return;
          if (_outgoing != null) {
            _fadeClock.reset();
            if (_active.isPlaying) _fadeClock.start();
            _fadeTimer = Timer.periodic(
                const Duration(milliseconds: 40), (_) => _tickFade());
          }
        } else {
          // Pending preparation is never awaited by an explicit user command.
          unawaited(_standby.stop());
          final gain = _active.setOutputGain(1);
          final playing = _active.playTrack(track);
          await Future.wait([gain, playing]);
        }
        _publish();
      });

  void _onDeckState(JustAudioPlayerService deck, PlayerState state) {
    if (_disposed || state != deck.state) return;
    if (identical(deck, _outgoing) && state.hasError) {
      _cancelFade();
      unawaited(_active.setOutputGain(1));
      unawaited(prepareNextTrack(_desiredNext));
      return;
    }
    if (identical(deck, _outgoing) &&
        state.status == PlayerPlaybackStatus.completed) {
      unawaited(_finishFade());
      return;
    }
    if (!identical(deck, _active)) {
      if (identical(deck, _standby) && state.hasError) _preparedTrack = null;
      return;
    }
    if (_outgoing != null) {
      if (state.hasError || state.status == PlayerPlaybackStatus.completed) {
        _cancelFade();
        unawaited(_active.setOutputGain(1));
      } else if (!state.isPlaying ||
          state.status != PlayerPlaybackStatus.playing) {
        _fadeClock.stop();
        unawaited(_outgoing!.pause());
      }
    }
    _publish();
    _maybeRequestTransition();
  }

  void _maybeRequestTransition() {
    if (_disposed ||
        _requestedTransition ||
        _outgoing != null ||
        _preparedTrack == null ||
        !_active.isPlaying ||
        _crossfadeDuration <= Duration.zero) {
      return;
    }
    final remaining = _active.transitionRemaining;
    if (remaining == null ||
        remaining <= Duration.zero ||
        remaining > _crossfadeDuration) {
      return;
    }
    _requestedTransition = true;
    _requests.add(_preparedTrack!);
  }

  void _tickFade() {
    if (_disposed ||
        _outgoing == null ||
        _gainUpdate != null ||
        !_active.isPlaying ||
        _active.state.status != PlayerPlaybackStatus.playing) {
      return;
    }
    if (!_fadeClock.isRunning) {
      _fadeClock.start();
      unawaited(_outgoing!.play());
    }
    final fraction =
        (_fadeClock.elapsedMicroseconds / _fadeDuration.inMicroseconds)
            .clamp(0.0, 1.0);
    if (fraction >= 1) {
      unawaited(_finishFade());
    } else {
      final outgoing = _outgoing!;
      final revision = _commandRevision;
      // Complementary linear gains prevent a two-track volume peak.
      _gainUpdate = Future.wait([
        _active.setOutputGain(fraction),
        outgoing.setOutputGain(1 - fraction),
      ]).then<void>((_) {}, onError: (Object _, StackTrace __) {
        if (!_disposed && revision == _commandRevision) {
          _cancelFade();
          unawaited(_active.setOutputGain(1));
        }
      }).whenComplete(() => _gainUpdate = null);
    }
  }

  Future<void> _finishFade() => _operations.run(() async {
        final outgoing = _outgoing;
        if (outgoing == null || _disposed || _finishingFade) return;
        _finishingFade = true;
        final revision = _commandRevision;
        _fadeTimer?.cancel();
        _fadeTimer = null;
        _fadeClock.stop();
        try {
          await outgoing.setOutputGain(0);
          if (_disposed || revision != _commandRevision) return;
          await outgoing.finishCrossfade();
          if (_disposed || revision != _commandRevision) return;
          _outgoing = null;
          await _active.setOutputGain(1);
          await prepareNextTrack(_desiredNext);
        } finally {
          _finishingFade = false;
        }
      });

  void _cancelFade() {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _fadeClock
      ..stop()
      ..reset();
    final outgoing = _outgoing;
    _outgoing = null;
    if (outgoing != null) unawaited(outgoing.stop());
  }

  @override
  Future<void> play() => _operations.run(() async {
        if (_disposed) return;
        await _active.play();
        if (_disposed) return;
        if (_outgoing != null && _active.isPlaying) {
          await _outgoing!.play();
          _fadeClock.start();
        }
      });

  @override
  Future<void> pause() => _operations.run(() async {
        if (_disposed) return;
        _fadeClock.stop();
        final outgoing = _outgoing;
        await Future.wait(
            [_active.pause(), if (outgoing != null) outgoing.pause()]);
      });

  @override
  Future<void> stop() => _operations.run(() async {
        if (_disposed) return;
        _commandRevision++;
        _preparationRevision++;
        _preparedTrack = null;
        _desiredNext = null;
        _cancelFade();
        await Future.wait(_decks.map((deck) => deck.stop()));
        _publish();
      });

  @override
  Future<void> seek(Duration position) => _operations.run(() async {
        if (_disposed) return;
        _cancelFade();
        _requestedTransition = false;
        await Future.wait([_active.setOutputGain(1), _active.seek(position)]);
        await prepareNextTrack(_desiredNext);
      });

  @override
  Future<void> setVolume(double volume) => _operations.run(() async {
        if (_disposed) return;
        await _decks.first.setVolume(volume);
        if (_disposed) return;
        _volume = _decks.first.volume;
        await _decks.last.setVolume(_volume);
        _publish();
      });

  @override
  Future<void> increaseVolume() => setVolume(_volume + .05);
  @override
  Future<void> decreaseVolume() => setVolume(_volume - .05);
  @override
  Future<void> toggleMute() => _operations.run(() async {
        if (_disposed) return;
        await _decks.first.toggleMute();
        if (_disposed) return;
        _volume = _decks.first.volume;
        await _decks.last.setVolume(_volume);
        _publish();
      });

  void _publish() {
    if (_disposed) return;
    final state = _active.state.copyWith(volume: _volume);
    if (state == _state) return;
    _state = state;
    _states.add(state);
  }

  @override
  Future<void> dispose() {
    if (_closing != null) return _closing!;
    _disposed = true;
    _operations.closeAdmission();
    _preparationRevision++;
    _commandRevision++;
    _fadeTimer?.cancel();
    _fadeClock.stop();
    // Start both decoders before waiting: either may own a pending source load.
    final decksClosing = _decks.map((deck) => deck.dispose()).toList();
    for (final closing in decksClosing) {
      closing.ignore();
    }
    return _closing = finishCleanup([
      for (final subscription in _subscriptions) subscription.cancel,
      () async {
        await Future.wait(decksClosing);
      },
      _operations.drain,
      () async {
        await _gainUpdate;
      },
      _states.close,
      _requests.close,
      _settingsChanges.close,
    ]);
  }
}
