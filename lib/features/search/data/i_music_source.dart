import '../../../core/models/track.dart';

abstract class IMusicSource {
  String get sourceId;

  Future<List<Track>> search(String query);

  Future<String> resolveStreamUrl(Track track);
}
