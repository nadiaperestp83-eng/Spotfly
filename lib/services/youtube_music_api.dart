// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:get/get.dart' as getx;

import 'constant.dart';

/// Cliente para a API interna do YouTube Music (youtubei/v1).
/// Faz requisições POST com os mesmos parâmetros que o Python ytmusicapi usa.
class YouTubeMusicApi extends getx.GetxService {
  final http.Client _client = http.Client();

  // ============================================================
  //  MÉTODO PRIVADO PARA REQUISIÇÕES
  // ============================================================
  Future<Map<String, dynamic>> _post(String endpoint,
      {Map<String, dynamic>? data, Map<String, String>? additionalHeaders}) async {
    try {
      final url = Uri.parse('$baseUrl$endpoint$fixedParms');

      final headers = {
        'User-Agent': userAgent,
        'Content-Type': 'application/json',
        'Accept': '*/*',
        'Accept-Encoding': 'gzip, deflate',
        'Origin': domain,
      };
      if (additionalHeaders != null) headers.addAll(additionalHeaders);

      // Dados base: inclui contexto do cliente
      final Map<String, dynamic> requestData = {
        ..._buildContext(),
        ...?data,
      };

      printINFO("📡 POST $endpoint");
      final response = await _client
          .post(url, headers: headers, body: jsonEncode(requestData))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        printINFO("✅ $endpoint OK");
        return decoded;
      } else {
        throw Exception("HTTP ${response.statusCode}: ${response.body}");
      }
    } catch (e) {
      printERROR("❌ Erro no POST $endpoint: $e");
      rethrow;
    }
  }

  // ============================================================
  //  CONTEXTO DO CLIENTE (mesmo do ytmusicapi)
  // ============================================================
  Map<String, dynamic> _buildContext() {
    return {
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': '1.20230213.01.00',
          'hl': 'en',
        },
        'user': {},
      }
    };
  }

  // ============================================================
  //  MÉTODOS PÚBLICOS
  // ============================================================

  // ------------------------------------------------------------------
  // 1. SEARCH
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> search(String query, {int limit = 30}) async {
    final data = {
      'query': query,
      'limit': limit,
      'params': getSearchParams(null, null, false), // padrão
    };
    return await _post('search', data: data);
  }

  // ------------------------------------------------------------------
  // 2. BROWSE (Home, Charts, Artist, Album, Playlist)
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> browse(String browseId,
      {String? params, Map<String, dynamic>? additionalData}) async {
    final data = {
      'browseId': browseId,
      ...?additionalData,
    };
    if (params != null) data['params'] = params;
    return await _post('browse', data: data);
  }

  // ------------------------------------------------------------------
  // 3. NEXT (Watch Playlist / Related)
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> next(String videoId,
      {String? playlistId, bool isAudioOnly = true}) async {
    final data = {
      'videoId': videoId,
      'playlistId': playlistId,
      'enablePersistentPlaylistPanel': true,
      'isAudioOnly': isAudioOnly,
    };
    return await _post('next', data: data);
  }

  // ------------------------------------------------------------------
  // 4. PLAYER (para obter URL de áudio, se necessário)
  //    Mas já temos stream_service.dart para isso.
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> player(String videoId) async {
    final data = {
      'videoId': videoId,
      'playbackContext': {
        'contentPlaybackContext': {
          'signatureTimestamp': getDatestamp() - 1,
        },
      },
    };
    return await _post('player', data: data);
  }

  // ============================================================
  //  UTILITÁRIOS
  // ============================================================
  String getSearchParams(String? filter, String? scope, bool ignoreSpelling) {
    // Implementação simplificada – você pode expandir conforme necessário
    // Baseado no código original que você tinha
    if (filter != null) {
      switch (filter.toLowerCase()) {
        case 'songs':
          return 'EgWKAQIIAWoKEAoQCRADEAA%3D';
        case 'videos':
          return 'EgWKAQIIAWoKEAoQCRADEAA%3D';
        case 'albums':
          return 'EgWKAQIIAWoKEAoQCRADEAA%3D';
        case 'artists':
          return 'EgWKAQIIAWoKEAoQCRADEAA%3D';
        case 'playlists':
          return 'EgWKAQIIAWoKEAoQCRADEAA%3D';
        default:
          return '';
      }
    }
    return '';
  }

  int getDatestamp() {
    // Retorna timestamp atual em segundos (simplificado)
    return DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  @override
  void onClose() {
    _client.close();
    super.onClose();
  }
}
