// ignore_for_file: constant_identifier_names

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart' as getx;
import 'package:hive/hive.dart';

import '/models/album.dart';
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
  // ⚠️ ALTERE ESTA URL PARA A DO SEU SERVIDOR PROXY
  static const String _proxyBaseUrl =
      'https://meu-api-proxy-music-production.up.railway.app';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _proxyBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  // ============================================================
  //  MÉTODOS DE INICIALIZAÇÃO (simplificados)
  // ============================================================
  @override
  void onInit() {
    super.onInit();
    printINFO("🎵 MusicServices usando proxy em: $_proxyBaseUrl");
  }

  set hlCode(String code) {
    printINFO("hlCode set to: $code (ignorado pelo proxy)");
  }

  // ============================================================
  //  MÉTODO PRIVADO PARA REQUISIÇÕES
  // ============================================================
  Future<dynamic> _get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    try {
      final response = await _dio.get(
        endpoint,
        queryParameters: queryParams,
      );
      if (response.statusCode == 200) {
        return response.data;
      } else {
        throw NetworkError("Erro ${response.statusCode}: ${response.statusMessage}");
      }
    } on DioException catch (e) {
      printERROR("Erro na requisição para $endpoint: $e");
      throw NetworkError("Falha na comunicação com o proxy: ${e.message}");
    } catch (e) {
      printERROR("Erro inesperado: $e");
      throw NetworkError("Erro inesperado: $e");
    }
  }

  // ============================================================
  //  MÉTODOS PÚBLICOS REFATORADOS
  // ============================================================

  // ------------------------------------------------------------------
  // 1. SEARCH - /search?q=...
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> search(
    String query, {
    String? filter,
    String? scope,
    int limit = 30,
    bool ignoreSpelling = false,
    String? filterParams,
  }) async {
    try {
      final Map<String, dynamic> params = {
        'q': query,
        'limit': limit,
      };
      if (filter != null) params['filter'] = filter;
      if (filterParams != null) params['filterParams'] = filterParams;

      final data = await _get('/search', queryParams: params);
      final results = data['results'] ?? [];
      return _categorizeSearchResults(results);
    } catch (e) {
      printERROR("Erro no search: $e");
      return {};
    }
  }

  // ------------------------------------------------------------------
  // 2. GET HOME - não suportado
  // ------------------------------------------------------------------
  Future<dynamic> getHome({int limit = 4}) async {
    printINFO("⚠️ getHome não suportado pelo proxy. Retornando lista vazia.");
    return [];
  }

  // ------------------------------------------------------------------
  // 3. GET CHARTS - não suportado
  // ------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getCharts(String category,
      {String? countryCode}) async {
    printINFO("⚠️ getCharts não suportado pelo proxy. Retornando vazio.");
    return [];
  }

  // ------------------------------------------------------------------
  // 4. GET WATCH PLAYLIST - usando /get_song e /get_playlist
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
        final songData = await _get('/get_song', queryParams: {'videoId': videoId});
        final track = _extractTrackFromSong(songData);
        return {
          'tracks': [track],
          'playlistId': playlistId ?? '',
          'lyrics': null,
          'related': null,
          'additionalParamsForNext': null,
        };
      } else if (playlistId != null) {
        final playlistData = await _get('/get_playlist', queryParams: {'playlistId': playlistId});
        final tracks = playlistData['tracks'] ?? [];
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
  // 5. GET PLAYLIST OR ALBUM SONGS
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
        final data = await _get('/get_playlist', queryParams: {'playlistId': playlistId});
        return _formatPlaylistData(data);
      } else if (albumId != null) {
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
  // 6. GET ARTIST - stub (não implementado no proxy)
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
  // 7. GET ARTIST RELATED CONTENT (nome correto)
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getArtistRelatedContent(
    String artistId,
    String tabName, {
    int limit = 10,
    Map<String, dynamic>? additionalParams,
  }) async {
    printINFO("⚠️ getArtistRelatedContent não implementado no proxy. Retornando vazio.");
    return {
      'contents': [],
      'additionalParams': {},
    };
  }

  // ⚠️ MÉTODO COM O NOME EXATO QUE O CONTROLLER ESPERA (com typo)
  // Este método chama o correto internamente para manter compatibilidade.
  Future<Map<String, dynamic>> getArtistRealtedContent(
    String artistId,
    String tabName, {
    int limit = 10,
    Map<String, dynamic>? additionalParams,
  }) async {
    // Redireciona para o método com nome correto
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
    printINFO("⚠️ getSearchContinuation não suportado pelo proxy.");
    return {};
  }

  // ------------------------------------------------------------------
  // 9. GET SONG YEAR - via /get_song
  // ------------------------------------------------------------------
  Future<String> getSongYear(String songId) async {
    try {
      final data = await _get('/get_song', queryParams: {'videoId': songId});
      final year = data['year'] ?? data['publishedDate'] ?? '';
      if (year is String && year.isNotEmpty) {
        final match = RegExp(r'\d{4}').firstMatch(year);
        return match?.group(0) ?? DateTime.now().year.toString();
      }
      return DateTime.now().year.toString();
    } catch (_) {
      return DateTime.now().year.toString();
    }
  }

  // ------------------------------------------------------------------
  // 10. GET SONG WITH ID (para deep links) - via /get_song
  // ------------------------------------------------------------------
  Future<List> getSongWithId(String songId) async {
    try {
      final data = await _get('/get_song', queryParams: {'videoId': songId});
      if (data.isNotEmpty) {
        final track = _extractTrackFromSong(data);
        return [true, [track]];
      }
      return [false, null];
    } catch (_) {
      return [false, null];
    }
  }

  // ------------------------------------------------------------------
  // 11. GET LYRICS - não suportado
  // ------------------------------------------------------------------
  dynamic getLyrics(String browseId) {
    printINFO("⚠️ getLyrics não suportado pelo proxy.");
    return '';
  }

  // ------------------------------------------------------------------
  // 12. GET CONTENT RELATED TO SONG - stub
  // ------------------------------------------------------------------
  dynamic getContentRelatedToSong(String videoId, String hlCode) {
    printINFO("⚠️ getContentRelatedToSong não suportado pelo proxy.");
    return [];
  }

  // ------------------------------------------------------------------
  // 13. GET SEARCH SUGGESTIONS - stub
  // ------------------------------------------------------------------
  Future<List<String>> getSearchSuggestion(String queryStr) async {
    printINFO("⚠️ getSearchSuggestion não suportado pelo proxy.");
    return [];
  }

  // ============================================================
  //  FUNÇÕES AUXILIARES DE FORMATAÇÃO
  // ============================================================

  Map<String, dynamic> _categorizeSearchResults(List<dynamic> results) {
    final Map<String, List<dynamic>> categories = {
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
