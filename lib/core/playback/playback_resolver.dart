import '../../features/search/data/i_music_source.dart';
import '../models/track.dart';
import 'i_playback_resolver.dart';

class PlaybackResolver implements IPlaybackResolver {
  final Map<String, IMusicSource> _sourcesById;

  PlaybackResolver(List<IMusicSource> sources)
      : _sourcesById = {for (final s in sources) s.sourceId: s};

  @override
  Future<String> resolve(Track track) async {
    final source = _sourcesById[track.sourceId];
    if (source == null) {
      throw StateError('Fonte "${track.sourceId}" não registrada.');
    }
    return source.resolveStreamUrl(track);
  }
}
