import '../domain/models/models.dart';
import 'metadata_match.dart';

abstract interface class AcousticIdentifierService {
  Future<List<MetadataMatch>> identify(Track track);
}

final class NoopAcousticIdentifierService implements AcousticIdentifierService {
  const NoopAcousticIdentifierService();

  @override
  Future<List<MetadataMatch>> identify(Track track) async {
    return const [];
  }
}
