import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../../core/models/track.dart';
import '../i_music_source.dart';

class YoutubeSource implements IMusicSource {
  final YoutubeExplode _yt = YoutubeExplode();

  @override
  String get sourceId => 'youtube';

  @override
  Future<List<Track>> search(String query) async {
    try {
      final results = await _yt.search.search(query);
      return results.whereType<Video>().map((v) {
        return Track(
          id: '${sourceId}_${v.id.value}',
          title: v.title,
          artist: v.author,
          artworkUrl: v.thumbnails.highResUrl,
          duration: v.duration,
          sourceId: sourceId,
          sourceTrackId: v.id.value,
          bitrateKbps: 160,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<String> resolveStreamUrl(Track track) async {
    final manifest =
        await _yt.videos.streamsClient.getManifest(track.sourceTrackId);
    final audio = manifest.audioOnly.withHighestBitrate();
    return audio.url.toString();
  }
}
