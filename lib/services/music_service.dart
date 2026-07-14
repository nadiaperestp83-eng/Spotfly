// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart' as getx;
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:yt_flutter_musicapi/yt_flutter_musicapi.dart';

import '../utils/helper.dart';

// ============================================================
//  DEFINIÇÃO DA EXCEÇÃO NetworkError
// ============================================================
class NetworkError implements Exception {
  final String message;
  NetworkError([this.message = "Network error occurred"]);
  @override
  String toString() => message;
}

enum AudioQuality {
  Low,
  High,
}

class MusicServices extends getx.GetxService {
  // ============================================================
  //  CONFIGURAÇÃO DO PROXY
  // ============================================================
  static const String _proxyBaseUrl =
      'https://yt-proxy-music-production.up.railway.app';

  // ============================================================
  //  INSTÂNCIA DO PACOTE YT_FLUTTER_MUSICAPI (apenas para busca)
  // ============================================================
  final YtFlutterMusicapi _ytApi = YtFlutterMusicapi();
  bool _ytApiReady = false;

  // ============================================================
  //  INICIALIZAÇÃO
  // ============================================================
  @override
  void onInit() {
    super.onInit();
    _initYtApi();
    printINFO("🎵 MusicServices usando proxy: $_proxyBaseUrl");
  }

  Future<void> _initYtApi() async {
    try {
      await _ytApi.initialize(country: 'BR');
      _ytApiReady = true;
      printINFO("✅ YtFlutterMusicapi inicializado com sucesso!");
    } catch (e) {
      printERROR("❌ Falha ao inicializar YtFlutterMusicapi: $e");
      _ytApiReady = false;
    }
  }

  set hlCode(String code) {
    printINFO("hlCode set to: $code (ignorado)");
  }

  // ============================================================
  //  MÉTODO PARA REQUISIÇÕES AO PROXY
  // ============================================================
  Future<dynamic> _get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    try {
      final uri = Uri.parse('$_proxyBaseUrl$endpoint')
          .replace(queryParameters: queryParams?.map((k, v) => MapEntry(k, v.toString())));
      
      printINFO("📡 GET $uri");
      
      final response = await http.get(uri).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw NetworkError("Timeout ao conectar ao proxy"),
      );
      
      printINFO("✅ Status: ${response.statusCode}");
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        printINFO("📦 Dados recebidos: ${data.keys}");
        return data;
      } else {
        throw NetworkError("Erro ${response.statusCode}: ${response.body}");
      }
    } catch (e) {
      printERROR("❌ Erro no proxy: $e");
      rethrow;
    }
  }

  // ============================================================
  //  MÉTODOS PÚBLICOS
  // ============================================================

  // ------------------------------------------------------------------
  // 1. SEARCH - tenta YtApi (com searchMusic), fallback proxy
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> search(
    String query, {
    String? filter,
    String? scope,
    int limit = 30,
    bool ignoreSpelling = false,
    String? filterParams,
  }) async {
    // Primeiro tenta o YtApi (se disponível)
    if (_ytApiReady) {
      try {
        printINFO("🔍 Buscando com YtFlutterMusicapi: '$query'");
        // O método correto é searchMusic(query, limit) - ambos obrigatórios?
        // A versão anterior aceitava apenas query, mas vamos tentar com limite
        final results = await _ytApi.searchMusic(query, limit);
        printINFO("📊 YtApi retornou ${results.length} resultados");
        return _categorizeYtResults(results);
      } catch (e) {
        printINFO("⚠️ YtApi falhou: $e. Usando fallback proxy.");
      }
    }

    // Fallback para proxy
    try {
      printINFO("🔍 Buscando via proxy: '$query'");
      final Map<String, dynamic> params = {
        'q': query,
        'limit': limit,
      };
      if (filter != null) params['filter'] = filter;
      if (filterParams != null) params['filterParams'] = filterParams;

      final data = await _get('/search', queryParams: params);
      
      if (data != null && data.containsKey('results')) {
        final results = data['results'] as List? ?? [];
        if (results.isNotEmpty) {
          printINFO("✅ Proxy retornou ${results.length} resultados");
          return _categorizeSearchResults(results);
        }
      }
      printINFO("⚠️ Proxy retornou vazio.");
    } catch (e) {
      printINFO("⚠️ Proxy falhou: $e");
    }

    printERROR("❌ Todas as fontes falharam para busca.");
    return {};
  }

  // ------------------------------------------------------------------
  // 2. GET HOME - usa proxy (pacote não tem getHome)
  // ------------------------------------------------------------------
  Future<dynamic> getHome({int limit = 4}) async {
    printINFO("🏠 Buscando Home via proxy...");
    try {
      // O proxy pode não ter /home, então retornamos vazio com aviso
      // Se quiser, pode implementar um endpoint /home no proxy
      printINFO("⚠️ getHome não implementado no proxy. Retornando lista vazia.");
      return [];
    } catch (e) {
      printERROR("❌ Erro no getHome: $e");
      return [];
    }
  }

  // ------------------------------------------------------------------
  // 3. GET CHARTS - usa proxy
  // ------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getCharts(String category,
      {String? countryCode}) async {
    printINFO("⚠️ getCharts não suportado pelo proxy. Retornando vazio.");
    return [];
  }

  // ------------------------------------------------------------------
  // 4. GET WATCH PLAYLIST - usa proxy
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getWatchPlaylist({
    String videoId = "",
    String? playlistId,
    int limit = 25,
    bool radio = false,
    bool shuffle = false,
    String? additionalParamsNext,
    bool onlyRelated = false,
  }) async {
    try {
      if (videoId.isNotEmpty) {
        printINFO("🎵 Obtendo música via proxy: $videoId");
        final data = await _get('/get_song', queryParams: {'videoId': videoId});
        final track = _extractTrackFromSong(data);
        return {
          'tracks': [track],
          'playlistId': playlistId ?? '',
          'lyrics': null,
          'related': null,
          'additionalParamsForNext': null,
        };
      } else if (playlistId != null) {
        printINFO("📋 Obtendo playlist via proxy: $playlistId");
        final data = await _get('/get_playlist', queryParams: {'playlistId': playlistId});
        final tracks = data['tracks'] ?? [];
        return {
          'tracks': tracks,
          'playlistId': playlistId,
          'lyrics': null,
          'related': null,
          'additionalParamsForNext': null,
        };
      }
      return {'tracks': [], 'playlistId': '', 'lyrics': null, 'related': null, 'additionalParamsForNext': null};
    } catch (e) {
      printERROR("Erro no getWatchPlaylist: $e");
      return {'tracks': [], 'playlistId': '', 'lyrics': null, 'related': null, 'additionalParamsForNext': null};
    }
  }

  // ------------------------------------------------------------------
  // 5. GET PLAYLIST OR ALBUM SONGS - usa proxy
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getPlaylistOrAlbumSongs({
    String? playlistId,
    String? albumId,
    int limit = 3000,
    bool related = false,
    int suggestionsLimit = 0,
  }) async {
    try {
      if (playlistId != null) {
        printINFO("📋 Obtendo playlist via proxy: $playlistId");
        final data = await _get('/get_playlist', queryParams: {'playlistId': playlistId});
        return _formatPlaylistData(data);
      } else if (albumId != null) {
        printINFO("📀 Obtendo álbum via proxy: $albumId");
        final data = await _get('/get_album', queryParams: {'browseId': albumId});
        return _formatAlbumData(data);
      }
      return {};
    } catch (e) {
      printERROR("Erro no getPlaylistOrAlbumSongs: $e");
      return {};
    }
  }

  // ------------------------------------------------------------------
  // 6. GET ARTIST - usa proxy (ou stub)
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getArtist(String artistId) async {
    printINFO("⚠️ getArtist não implementado no proxy. Retornando stub.");
    return {
      'id': artistId,
      'name': 'Artist $artistId',
      'thumbnails': [],
      'description': '',
      'subscribers': '0',
      'radioId': '',
    };
  }

  // ------------------------------------------------------------------
  // 7. GET ARTIST RELATED CONTENT - stub
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getArtistRelatedContent(
    String artistId,
    String tabName, {
    int limit = 10,
    Map<String, dynamic>? additionalParams,
  }) async {
    printINFO("⚠️ getArtistRelatedContent não implementado. Retornando vazio.");
    return {
      'contents': [],
      'additionalParams': {},
    };
  }

  // Método com typo para compatibilidade
  Future<Map<String, dynamic>> getArtistRealtedContent(
    String artistId,
    String tabName, {
    int limit = 10,
    Map<String, dynamic>? additionalParams,
  }) async {
    return getArtistRelatedContent(artistId, tabName,
        limit: limit, additionalParams: additionalParams);
  }

  // ------------------------------------------------------------------
  // 8. GET SEARCH CONTINUATION - stub
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getSearchContinuation(
    Map<String, dynamic> continuationParams, {
    int limit = 10,
  }) async {
    printINFO("⚠️ getSearchContinuation não suportado.");
    return {};
  }

  // ------------------------------------------------------------------
  // 9. GET SONG YEAR - via proxy
  // ------------------------------------------------------------------
  Future<String> getSongYear(String songId) async {
    try {
      final data = await _get('/get_song', queryParams: {'videoId': songId});
      final year = data['year'] ?? data['publishedDate'] ?? '';
      if (year is String && year.isNotEmpty) {
        final match = RegExp(r'\d{4}').firstMatch(year);
        return match?.group(0) ?? DateTime.now().year.toString();
      }
    } catch (_) {}
    return DateTime.now().year.toString();
  }

  // ------------------------------------------------------------------
  // 10. GET SONG WITH ID - via proxy
  // ------------------------------------------------------------------
  Future<List> getSongWithId(String songId) async {
    try {
      final data = await _get('/get_song', queryParams: {'videoId': songId});
      if (data.isNotEmpty) {
        final track = _extractTrackFromSong(data);
        return [true, [track]];
      }
    } catch (_) {}
    return [false, null];
  }

  // ------------------------------------------------------------------
  // 11. GET LYRICS - não suportado
  // ------------------------------------------------------------------
  dynamic getLyrics(String browseId) {
    printINFO("⚠️ getLyrics não suportado.");
    return '';
  }

  // ------------------------------------------------------------------
  // 12. GET CONTENT RELATED TO SONG - stub
  // ------------------------------------------------------------------
  dynamic getContentRelatedToSong(String videoId, String hlCode) {
    printINFO("⚠️ getContentRelatedToSong não suportado.");
    return [];
  }

  // ------------------------------------------------------------------
  // 13. GET SEARCH SUGGESTIONS - stub
  // ------------------------------------------------------------------
  Future<List<String>> getSearchSuggestion(String queryStr) async {
    printINFO("⚠️ getSearchSuggestion não suportado.");
    return [];
  }

  // ============================================================
  //  FUNÇÕES AUXILIARES DE CONVERSÃO
  // ============================================================

  // --- Proxy results ---
  Map<String, dynamic> _categorizeSearchResults(List<dynamic> results) {
    final categories = {
      'Songs': [],
      'Videos': [],
      'Albums': [],
      'Artists': [],
      'Featured playlists': [],
      'Community playlists': [],
    };

    for (var item in results) {
      if (item is! Map) continue;
      final type = item['resultType']?.toString() ?? '';
      final title = item['title']?.toString() ?? '';
      final id = item['browseId']?.toString() ?? item['playlistId']?.toString() ?? '';

      switch (type.toLowerCase()) {
        case 'song':
        case 'track':
          categories['Songs']!.add(item);
          break;
        case 'video':
          categories['Videos']!.add(item);
          break;
        case 'album':
          categories['Albums']!.add(item);
          break;
        case 'artist':
        case 'channel':
          categories['Artists']!.add(item);
          break;
        case 'playlist':
          if (title.toLowerCase().contains('community') || id.contains('community')) {
            categories['Community playlists']!.add(item);
          } else {
            categories['Featured playlists']!.add(item);
          }
          break;
        default:
          if (item.containsKey('videoId') && item.containsKey('title')) {
            categories['Songs']!.add(item);
          } else if (item.containsKey('browseId') && item.containsKey('trackCount')) {
            categories['Albums']!.add(item);
          } else if (item.containsKey('playlistId')) {
            categories['Featured playlists']!.add(item);
          }
      }
    }

    categories.removeWhere((key, value) => value.isEmpty);
    return categories;
  }

  Map<String, dynamic> _extractTrackFromSong(Map<String, dynamic> songData) {
    return {
      'videoId': songData['videoId'] ?? '',
      'title': songData['title'] ?? '',
      'artists': songData['artists'] ?? [],
      'album': songData['album'] ?? {},
      'thumbnails': songData['thumbnails'] ?? [],
      'duration': songData['duration'] ?? 0,
      'year': songData['year'] ?? '',
      'playlistId': songData['playlistId'] ?? '',
    };
  }

  // --- YtApi results ---
  Map<String, dynamic> _categorizeYtResults(List<dynamic> results) {
    final categories = {
      'Songs': [],
      'Videos': [],
      'Albums': [],
      'Artists': [],
      'Featured playlists': [],
      'Community playlists': [],
    };

    for (var item in results) {
      try {
        final json = item.toJson();
        final type = json['type']?.toString() ?? '';
        final title = json['title']?.toString() ?? '';
        final id = json['id']?.toString() ?? '';

        switch (type.toLowerCase()) {
          case 'song':
            categories['Songs']!.add(_convertYtSong(json));
            break;
          case 'video':
            categories['Videos']!.add(_convertYtVideo(json));
            break;
          case 'album':
            categories['Albums']!.add(_convertYtAlbum(json));
            break;
          case 'artist':
            categories['Artists']!.add(_convertYtArtist(json));
            break;
          case 'playlist':
            if (title.toLowerCase().contains('community') || id.contains('community')) {
              categories['Community playlists']!.add(_convertYtPlaylist(json));
            } else {
              categories['Featured playlists']!.add(_convertYtPlaylist(json));
            }
            break;
          default:
            if (json.containsKey('videoId')) {
              categories['Songs']!.add(_convertYtSong(json));
            } else if (json.containsKey('browseId')) {
              categories['Albums']!.add(_convertYtAlbum(json));
            } else if (json.containsKey('playlistId')) {
              categories['Featured playlists']!.add(_convertYtPlaylist(json));
            }
        }
      } catch (e) {
        printERROR("Erro ao converter item YtApi: $e");
      }
    }

    categories.removeWhere((key, value) => value.isEmpty);
    return categories;
  }

  Map<String, dynamic> _convertYtSong(Map<String, dynamic> json) {
    return {
      'videoId': json['videoId'] ?? json['id'] ?? '',
      'title': json['title'] ?? '',
      'artists': json['artists'] ?? [],
      'album': json['album'] ?? {},
      'thumbnails': json['thumbnails'] ?? [],
      'duration': json['duration'] ?? 0,
      'year': json['year'] ?? '',
      'playlistId': json['playlistId'] ?? '',
      'resultType': 'song',
    };
  }

  Map<String, dynamic> _convertYtVideo(Map<String, dynamic> json) {
    return {
      'videoId': json['videoId'] ?? json['id'] ?? '',
      'title': json['title'] ?? '',
      'artists': json['artists'] ?? [],
      'thumbnails': json['thumbnails'] ?? [],
      'duration': json['duration'] ?? 0,
      'resultType': 'video',
    };
  }

  Map<String, dynamic> _convertYtAlbum(Map<String, dynamic> json) {
    return {
      'browseId': json['browseId'] ?? json['id'] ?? '',
      'title': json['title'] ?? '',
      'thumbnails': json['thumbnails'] ?? [],
      'trackCount': json['trackCount'] ?? 0,
      'year': json['year'] ?? '',
      'artists': json['artists'] ?? [],
      'resultType': 'album',
    };
  }

  Map<String, dynamic> _convertYtArtist(Map<String, dynamic> json) {
    return {
      'browseId': json['browseId'] ?? json['id'] ?? '',
      'name': json['name'] ?? json['title'] ?? '',
      'thumbnails': json['thumbnails'] ?? [],
      'subscribers': json['subscribers']?.toString() ?? '0',
      'resultType': 'artist',
    };
  }

  Map<String, dynamic> _convertYtPlaylist(Map<String, dynamic> json) {
    return {
      'playlistId': json['playlistId'] ?? json['id'] ?? '',
      'title': json['title'] ?? '',
      'thumbnails': json['thumbnails'] ?? [],
      'trackCount': json['trackCount'] ?? 0,
      'resultType': 'playlist',
    };
  }

  // --- Formatação para compatibilidade ---
  Map<String, dynamic> _formatPlaylistData(Map<String, dynamic> data) {
    return {
      'id': data['id'] ?? '',
      'title': data['title'] ?? '',
      'thumbnails': data['thumbnails'] ?? [],
      'description': data['description'] ?? '',
      'trackCount': data['trackCount'] ?? 0,
      'duration': data['duration'] ?? '',
      'tracks': data['tracks'] ?? [],
      'author': data['author'] ?? {},
      'year': data['year'] ?? '',
      'duration_seconds': _sumTotalDuration(data['tracks'] ?? []),
    };
  }

  Map<String, dynamic> _formatAlbumData(Map<String, dynamic> data) {
    return {
      'id': data['id'] ?? '',
      'title': data['title'] ?? '',
      'thumbnails': data['thumbnails'] ?? [],
      'description': data['description'] ?? '',
      'trackCount': data['trackCount'] ?? 0,
      'tracks': data['tracks'] ?? [],
      'artists': data['artists'] ?? [],
      'year': data['year'] ?? '',
      'duration_seconds': _sumTotalDuration(data['tracks'] ?? []),
      'other_versions': data['other_versions'] ?? [],
    };
  }

  int _sumTotalDuration(List<dynamic> tracks) {
    int total = 0;
    for (var track in tracks) {
      if (track is Map && track.containsKey('duration')) {
        final dur = track['duration'];
        if (dur is int) total += dur;
        else if (dur is String) {
          try { total += int.parse(dur); } catch (_) {}
        }
      }
    }
    return total;
  }
}
