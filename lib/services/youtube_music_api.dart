// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/helper.dart';
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
      },
      'user': {}
    }
  };

  set hlCode(String code) {
    _context['context']['client']['hl'] = code;
  }

  Future<Map<String, dynamic>> _post(String endpoint, Map<String, dynamic> data) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint$fixedParms');
      printINFO("📡 POST $uri");
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        printINFO("✅ $endpoint OK");
        return jsonDecode(response.body);
      } else {
        throw NetworkError("Erro ${response.statusCode}: ${response.body}");
      }
    } catch (e) {
      printERROR("❌ Erro no POST $endpoint: $e");
      rethrow;
    }
  }

  // ============================================================
  //  SEARCH
  // ============================================================
  Future<Map<String, dynamic>> search(String query, {int limit = 30}) async {
    final data = Map.from(_context);
    data['context']['client']["hl"] = 'en';
    data['query'] = query;
    data['params'] = 'EgWKAQIIAWoKEAoQCRADEAA%3D'; // busca geral

    final response = await _post('search', data);
    return response;
  }

  // ============================================================
  //  BROWSE (para artistas, playlists, álbuns, charts, etc.)
  // ============================================================
  Future<Map<String, dynamic>> browse(String browseId, {Map<String, dynamic>? params}) async {
    final data = Map.from(_context);
    data['browseId'] = browseId;
    if (params != null) {
      data.addAll(params);
    }
    final response = await _post('browse', data);
    return response;
  }

  // ============================================================
  //  NEXT (para playlist de reprodução / watch playlist)
  // ============================================================
  Future<Map<String, dynamic>> next({
    required String videoId,
    String? playlistId,
    bool radio = false,
    bool shuffle = false,
  }) async {
    final data = Map.from(_context);
    data['enablePersistentPlaylistPanel'] = true;
    data['isAudioOnly'] = true;
    data['tunerSettingValue'] = 'AUTOMIX_SETTING_NORMAL';
    data['videoId'] = videoId;
    if (playlistId != null) {
      data['playlistId'] = playlistId;
    }
    if (shuffle) {
      data['params'] = "wAEB8gECKAE%3D";
    }
    if (radio) {
      data['params'] = "wAEB";
    }
    final response = await _post('next', data);
    return response;
  }

  // ============================================================
  //  PLAYER (para obter URL de áudio) - se necessário
  // ============================================================
  Future<Map<String, dynamic>> player(String videoId) async {
    final data = Map.from(_context);
    data['videoId'] = videoId;
    final response = await _post('player', data);
    return response;
  }
}
