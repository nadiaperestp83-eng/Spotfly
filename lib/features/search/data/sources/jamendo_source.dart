import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/models/search_result.dart';
import '../../../../core/models/track.dart';
import '../i_music_source.dart';
import '../track_media_item_mapper.dart';

class JamendoSource implements IMusicSource {
  final String clientId;
  static const _baseUrl = 'https://api.jamendo.com/v3.0/tracks';

  JamendoSource({required this.clientId});

  @override
  String get sourceId => 'jamendo';

  @override
  Future<SearchResult> search(
    String query, {
    String? filter,
    String? filterParams,
    int limit = 30,
  }) async {
    if (clientId.isEmpty) return const SearchResult(sourceId: 'jamendo');

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'client_id': clientId,
      'format': 'json',
      'limit': limit.toString(),
      'namesearch': query,
      'audioformat': 'mp32',
      'include': 'musicinfo',
    });

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return const SearchResult(sourceId: 'jamendo');

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (body['results'] as List<dynamic>? ?? []);
      final tracks = results.map(_trackFromJamendoItem).toList();

      if (tracks.isEmpty) return const SearchResult(sourceId: 'jamendo');

      return SearchResult(
        // Categoria 'Songs' simulada: Jamendo só tem faixas soltas, sem
        // Videos/Albums/Artists/Playlists separados.
        categories: {'Songs': tracks.map((t) => t.toFallbackMediaItem()).toList()},
        allTracks: tracks,
        sourceId: sourceId,
      );
    } catch (_) {
      return const SearchResult(sourceId: 'jamendo');
    }
  }

  @override
  Future<SearchResult> searchContinuation(
    Map<String, dynamic> continuationParams, {
    int limit = 10,
  }) async {
    // Jamendo não suporta paginação nesta integração.
    return const SearchResult(sourceId: 'jamendo');
  }

  @override
  Future<List<dynamic>> getHomeContent({int limit = 4}) async {
    if (clientId.isEmpty) return const [];

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'client_id': clientId,
      'format': 'json',
      'limit': '20',
      'order': 'popularity_month',
      'audioformat': 'mp32',
    });

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return const [];

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (body['results'] as List<dynamic>? ?? []);
      final tracks = results.map(_trackFromJamendoItem).toList();

      if (tracks.isEmpty) return const [];

      return [
        {
          'title': 'Populares no Jamendo',
          'contents': tracks.map((t) => t.toFallbackMediaItem()).toList(),
        }
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<String> resolveStreamUrl(Track track) async {
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'client_id': clientId,
      'format': 'json',
      'id': track.sourceTrackId,
      'audioformat': 'mp32',
    });

    final response = await http.get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final results = body['results'] as List<dynamic>;
    if (results.isEmpty) {
      throw StateError('Faixa Jamendo não encontrada: ${track.sourceTrackId}');
    }
    return results.first['audio'] as String;
  }

  Track _trackFromJamendoItem(dynamic item) {
    final map = item as Map<String, dynamic>;
    return Track(
      id: '${sourceId}_${map['id']}',
      title: map['name'] as String? ?? 'Sem título',
      artist: map['artist_name'] as String? ?? 'Desconhecido',
      artworkUrl: map['image'] as String? ?? '',
      duration: Duration(seconds: (map['duration'] as num?)?.toInt() ?? 0),
      sourceId: sourceId,
      sourceTrackId: map['id'].toString(),
      bitrateKbps: 320,
    );
  }
}
