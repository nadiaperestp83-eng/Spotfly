import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/models/track.dart';
import '../i_music_source.dart';

class JamendoSource implements IMusicSource {
  final String clientId;
  static const _baseUrl = 'https://api.jamendo.com/v3.0/tracks';

  JamendoSource({required this.clientId});

  @override
  String get sourceId => 'jamendo';

  @override
  Future<List<Track>> search(String query) async {
    if (clientId.isEmpty) return [];

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'client_id': clientId,
      'format': 'json',
      'limit': '20',
      'namesearch': query,
      'audioformat': 'mp32',
      'include': 'musicinfo',
    });

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return [];

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (body['results'] as List<dynamic>? ?? []);

      return results.map((item) {
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
      }).toList();
    } catch (_) {
      return [];
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
}
