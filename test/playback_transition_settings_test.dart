import 'dart:async';

import 'package:clever_music_player/src/domain/models/track.dart';
import 'package:clever_music_player/src/player/playback_transitions.dart';
import 'package:clever_music_player/src/ui/playback_transition_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('crossfade setting is usable at narrow width and can be disabled',
      (tester) async {
    final transitions = _Transitions();
    addTearDown(transitions.changes.close);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 320,
                child: PlaybackTransitionSettings(transitions: transitions)))));
    expect(find.text('Плавный переход: 3 с'), findsOneWidget);
    final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('crossfade-duration-slider')));
    slider.onChanged!(0);
    await tester.pump();
    await tester.pump();
    expect(find.text('Плавный переход выключен'), findsOneWidget);
    expect(transitions.crossfadeDuration, Duration.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed persistence keeps previous setting and offers retry',
      (tester) async {
    final transitions = _Transitions()..fail = true;
    addTearDown(transitions.changes.close);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PlaybackTransitionSettings(transitions: transitions))));
    tester.widget<Slider>(find.byType(Slider)).onChanged!(5);
    await tester.pump();
    await tester.pump();
    expect(
        find.text('Не удалось сохранить настройку перехода.'), findsOneWidget);
    expect(find.text('Плавный переход: 3 с'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
  });
}

class _Transitions implements PlaybackTransitions {
  final changes = StreamController<Duration>.broadcast();
  bool fail = false;
  @override
  Duration crossfadeDuration = const Duration(seconds: 3);
  @override
  Stream<Duration> get crossfadeDurationStream => changes.stream;
  @override
  Stream<Track> get automaticTransitionStream => const Stream.empty();
  @override
  Future<void> setCrossfadeDuration(Duration duration) async {
    if (fail) throw StateError('disk');
    crossfadeDuration = duration;
    changes.add(duration);
  }

  @override
  Future<void> prepareNextTrack(Track? track) async {}
  @override
  Future<void> playAutomatically(Track track) async {}
}
