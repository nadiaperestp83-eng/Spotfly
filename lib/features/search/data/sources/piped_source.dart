import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/models/search_result.dart';
import '../../../../core/models/track.dart';
import '../i_music_source.dart';
import '../track_media_item_mapper.dart';
import 'piped_instances.dart';

class PipedSource implements IMusicSource {
  static const _timeout = Duration(seconds: 5);

  @override
  String get sourceId => 'piped';

  @override
  Future<SearchResult> search(
    String query, {
    String? filter,
    String? filterParams,
    int limit = 30,
  }) async {
    final tracks = await _fetchSearchTracks(query);
    if (tracks.isEmpty) return const SearchResult(sourceId: 'piped');

    final limited = tracks.take(limit).toList();
    return SearchResult(
      // Categoria 'Songs' simulada: o Piped não tem o conceito de
      // Videos/Albums/Artists/Playlists separados, então tudo entra
      // aqui pra UI não quebrar.
      categories: {'Songs': limited.map((t) => t.toFallbackMediaItem()).toList()},
      allTracks: limited,
      sourceId: sourceId,
    );
  }

  @override
  Future<SearchResult> searchContinuation(
    Map<String, dynamic> continuationParams, {
    int limit = 10,
  }) async {
    // Piped não suporta paginação nesta integração.
    return const SearchResult(sourceId: 'piped');
  }

  @override
  Future<List<dynamic>> getHomeContent({int limit = 4}) async {
    for (final instance in pipedInstances) {
      try {
        final uri = Uri.parse('$instance/trending')
            .replace(queryParameters: {'region': 'US'});
        final response = await http.get(uri).timeout(_timeout);
        if (response.statusCode != 200) continue;

        final items = jsonDecode(response.body) as List<dynamic>;
        final tracks = items.map(_trackFromPipedItem).toList();

        if (tracks.isNotEmpty) {
          return [
            {
              'title': 'Em alta (Piped)',
              'contents': tracks.map((t) => t.toFallbackMediaItem()).toList(),
            }
          ];
        }
      } catch (_) {
        continue;
      }
    }
    return const [];
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

        audioStreams
            .sort((a, b) => (b['bitrate'] as num).compareTo(a['bitrate'] as num));
        return audioStreams.first['url'] as String;
      } catch (_) {
        continue;
      }
    }
    throw StateError('Nenhuma instância Piped respondeu para resolver stream.');
  }

  Future<List<Track>> _fetchSearchTracks(String query) async {
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

        return items
            .where((i) => i['type'] == 'stream')
            .map(_trackFromPipedItem)
            .toList();
      } catch (_) {
        continue;
      }
    }
    return [];
  }

  Track _trackFromPipedItem(dynamic item) {
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
  }

  String _extractVideoId(String pipedUrl) {
    final uri = Uri.tryParse(pipedUrl);
    return uri?.queryParameters['v'] ?? pipedUrl;
  }
}
