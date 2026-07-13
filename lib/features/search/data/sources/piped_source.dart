import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/models/track.dart';
import '../i_music_source.dart';
import 'piped_instances.dart';

class PipedSource implements IMusicSource {
  static const _timeout = Duration(seconds: 5);

  @override
  String get sourceId => 'piped';

  @override
  Future<List<Track>> search(String query) async {
    for (final instance in pipedInstances) {
      try {
        final uri = Uri.parse('$instance/search').replace(queryParameters: {
          'q': query,
          'filter': 'music_songs',
        });
        final response = await http.get(uri).timeout(_timeout);
        if (response.statusCode != 200) continue;

        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final items = body['items'] as List<dynamic>? ?? [];

        return items.where((i) => i['type'] == 'stream').map((item) {
          final map = item as Map<String, dynamic>;
          final videoId = _extractVideoId(map['url'] as String? ?? '');
          return Track(
            id: '${sourceId}_$videoId',
            title: map['title'] as String? ?? 'Sem título',
            artist: map['uploaderName'] as String? ?? 'Desconhecido',
            artworkUrl: map['thumbnail'] as String? ?? '',
            duration: Duration(seconds: (map['duration'] as num?)?.toInt() ?? 0),
            sourceId: sourceId,
            sourceTrackId: videoId,
            bitrateKbps: 128,
          );
        }).toList();
      } catch (_) {
        continue;
      }
    }
    return [];
  }

  @override
  Future<String> resolveStreamUrl(Track track) async {
    for (final instance in pipedInstances) {
      try {
        final uri = Uri.parse('$instance/streams/${track.sourceTrackId}');
        final response = await http.get(uri).timeout(_timeout);
        if (response.statusCode != 200) continue;

        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final audioStreams = body['audioStreams'] as List<dynamic>? ?? [];
        if (audioStreams.isEmpty) continue;

        audioStreams.sort((a, b) =>
            (b['bitrate'] as num).compareTo(a['bitrate'] as num));
        return audioStreams.first['url'] as String;
      } catch (_) {
        continue;
      }
    }
    throw StateError('Nenhuma instância Piped respondeu para resolver stream.');
  }

  String _extractVideoId(String pipedUrl) {
    final uri = Uri.tryParse(pipedUrl);
    return uri?.queryParameters['v'] ?? pipedUrl;
  }
}
