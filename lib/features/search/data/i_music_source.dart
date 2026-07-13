import '../../../core/models/track.dart';

/// Contrato que TODA fonte de música deve implementar.
/// SearchCoordinator e PlaybackResolver só falam com essa interface.
abstract class IMusicSource {
  String get sourceId;

  Future<List<Track>> search(String query);

  Future<String> resolveStreamUrl(Track track);
}
