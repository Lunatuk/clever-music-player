import 'dart:async';

import 'package:clever_music_player/src/domain/models/external_track_ref.dart';
import 'package:clever_music_player/src/library/library_track_variants.dart';

final class FakeLibraryVariantRepository implements LibraryVariantRepository {
  FakeLibraryVariantRepository(this.identities);

  final Map<int, Set<ExternalTrackIdentity>> identities;
  final _changes = StreamController<LibraryVariantEvidence>.broadcast();
  final _preferred = <ExternalTrackIdentity, int>{};

  LibraryVariantEvidence get _evidence => LibraryVariantEvidence(
      identities: identities, preferred: Map.of(_preferred));

  @override
  Stream<LibraryVariantEvidence> watchEvidence() async* {
    yield _evidence;
    yield* _changes.stream;
  }

  @override
  Future<void> setPreferred(
      ExternalTrackIdentity identity, int? trackId) async {
    if (trackId == null) {
      _preferred.remove(identity);
    } else {
      _preferred[identity] = trackId;
    }
    _changes.add(_evidence);
  }

  Future<void> close() => _changes.close();
}
