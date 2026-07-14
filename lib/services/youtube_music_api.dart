import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/helper.dart'; // <-- importa printINFO e printERROR
import 'constant.dart';

class YouTubeMusicApi {
  final Map<String, String> _headers = {
    'user-agent': userAgent,
    'accept': '*/*',
    'accept-encoding': 'gzip, deflate',
    'content-type': 'application/json',
    'content-encoding': 'gzip',
    'origin': domain,
    'cookie': 'CONSENT=YES+1',
  };

  final Map<String, dynamic> _context = {
    'context': {
      'client': {
        "clientName": "WEB_REMIX",
        "clientVersion": "1.20230213.01.00",
        "hl": "en",
      },
      'user': {}
    }
  };

  Future<Map<String, dynamic>> _post(String endpoint, Map<String, dynamic> data) async {
    final url = Uri.parse('$baseUrl$endpoint$fixedParms');
    try {
      printINFO("📡 POST $url");
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        printINFO("✅ $endpoint OK");
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception("Erro ${response.statusCode}: ${response.body}");
      }
    } catch (e) {
      printERROR("❌ Erro no POST $endpoint: $e");
      rethrow;
    }
  }

  // ============================================================
  //  MÉTODOS PÚBLICOS
  // ============================================================

  Future<Map<String, dynamic>> search(String query, {int limit = 30}) async {
    final Map<String, dynamic> data = Map.from(_context);
    data['query'] = query;
    // Parâmetro de filtro para músicas (songs)
    data['params'] = 'EgWKAQIIAWoKEAoQCRADEAA%3D'; 
    final response = await _post('search', data);
    return response;
  }

  Future<Map<String, dynamic>> getHome() async {
    final Map<String, dynamic> data = Map.from(_context);
    data['browseId'] = 'FEmusic_home';
    return await _post('browse', data);
  }

  Future<Map<String, dynamic>> getSong(String videoId) async {
    final Map<String, dynamic> data = Map.from(_context);
    data['videoId'] = videoId;
    data['playbackContext'] = {
      'contentPlaybackContext': {
        'signatureTimestamp': 1,
      }
    };
    return await _post('player', data);
  }

  Future<Map<String, dynamic>> getPlaylist(String playlistId) async {
    final Map<String, dynamic> data = Map.from(_context);
    data['browseId'] = 'VL$playlistId';
    return await _post('browse', data);
  }

  Future<Map<String, dynamic>> getAlbum(String albumId) async {
    final Map<String, dynamic> data = Map.from(_context);
    data['browseId'] = albumId;
    return await _post('browse', data);
  }

  Future<Map<String, dynamic>> getArtist(String artistId) async {
    final Map<String, dynamic> data = Map.from(_context);
    data['browseId'] = artistId;
    return await _post('browse', data);
  }

  Future<Map<String, dynamic>> getWatchPlaylist(String videoId) async {
    final Map<String, dynamic> data = Map.from(_context);
    data['videoId'] = videoId;
    data['playlistId'] = 'RDAMVM$videoId';
    data['enablePersistentPlaylistPanel'] = true;
    data['isAudioOnly'] = true;
    return await _post('next', data);
  }
}
