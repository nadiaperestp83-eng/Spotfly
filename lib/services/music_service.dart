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
    // Não precisamos mais de visitorId, headers manuais, etc.
    printINFO("🎵 MusicServices usando proxy em: $_proxyBaseUrl");
  }

  set hlCode(String code) {
    // O proxy pode ignorar ou usar isso se quiser, mas por enquanto não faz nada
    printINFO("hlCode set to: $code (ignorado pelo proxy)");
  }

  // ============================================================
  //  MÉTODO PRIVADO PARA REQUISIÇÕES (substitui _sendRequest)
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
      // O proxy atualmente não suporta filtros, mas podemos passar o limit
      final Map<String, dynamic> params = {
        'q': query,
        'limit': limit,
      };
      // Se o proxy futuramente suportar filtros, podemos adicionar
      if (filter != null) params['filter'] = filter;
      if (filterParams != null) params['filterParams'] = filterParams;

      final data = await _get('/search', queryParams: params);

      // O proxy retorna algo como: { "query": "...", "results": [...] }
      // Precisamos extrair os resultados e colocá-los no formato que as telas esperam
      final results = data['results'] ?? [];

      // Normaliza a saída: cria um mapa com categorias (Songs, Videos, etc.)
      // O proxy já retorna os dados estruturados pelo ytmusicapi, que inclui 'resultType'
      return _categorizeSearchResults(results);
    } catch (e) {
      printERROR("Erro no search: $e");
      return {};
    }
  }

  // ------------------------------------------------------------------
  // 2. GET HOME - como o proxy não tem /home, retornamos uma lista vazia
  //    (ou podemos usar uma busca com "top" ou similar, mas melhor retornar vazio)
  // ------------------------------------------------------------------
  Future<dynamic> getHome({int limit = 4}) async {
    printINFO("⚠️ getHome não suportado pelo proxy. Retornando lista vazia.");
    // Se quiser, pode chamar /search?q=top%20songs ou algo similar
    // Mas para não quebrar, retornamos lista vazia
    return [];
  }

  // ------------------------------------------------------------------
  // 3. GET CHARTS - O proxy não tem /charts, retornamos vazio
  // ------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getCharts(String category,
      {String? countryCode}) async {
    printINFO("⚠️ getCharts não suportado pelo proxy. Retornando vazio.");
    return [];
  }

  // ------------------------------------------------------------------
  // 4. GET WATCH PLAYLIST - usando /get_song para obter a música e extrair playlist?
  //    Não temos um endpoint específico. Vamos retornar uma estrutura básica.
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
      // Se tiver videoId, usa /get_song para obter a música e montar a playlist
      if (videoId.isNotEmpty) {
        final songData = await _get('/get_song', queryParams: {'videoId': videoId});
        // Extrai a playlist relacionada (se houver) do campo 'relatedPlaylists'? 
        // O ytmusicapi retorna isso no get_song? Não diretamente.
        // Vamos montar uma estrutura mínima com a música
        final track = _extractTrackFromSong(songData);
        return {
          'tracks': [track],
          'playlistId': playlistId ?? '',
          'lyrics': null,
          'related': null,
          'additionalParamsForNext': null,
        };
      } else if (playlistId != null) {
        // Se tiver playlistId, usa /get_playlist
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
        // Ajusta para o formato que o app espera (similar ao antigo parse)
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
  // 6. GET ARTIST - /get_artist?browseId=...
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getArtist(String artistId) async {
    try {
      // O proxy ainda não tem /get_artist, mas podemos usar /search?q=artistId
      // ou adicionar no proxy. Vamos retornar um stub.
      printINFO("⚠️ getArtist não implementado no proxy. Retornando stub.");
      return {
        'id': artistId,
        'name': 'Artist $artistId',
        'thumbnails': [],
        'description': '',
        'subscribers': '0',
        'radioId': '',
      };
    } catch (e) {
      printERROR("Erro no getArtist: $e");
      return {
        'id': artistId,
        'name': 'Unknown Artist',
        'thumbnails': [],
        'description': '',
      };
    }
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
    printINFO("⚠️ getArtistRelatedContent não implementado no proxy. Retornando vazio.");
    return {
      'contents': [],
      'additionalParams': {},
    };
  }

  // ------------------------------------------------------------------
  // 8. GET SEARCH CONTINUATION - stub (scroll infinito)
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getSearchContinuation(
    Map<String, dynamic> continuationParams, {
    int limit = 10,
  }) async {
    // O proxy não suporta continuação. Retornamos vazio.
    printINFO("⚠️ getSearchContinuation não suportado pelo proxy.");
    return {};
  }

  // ------------------------------------------------------------------
  // 9. GET SONG YEAR - via /get_song
  // ------------------------------------------------------------------
  Future<String> getSongYear(String songId) async {
    try {
      final data = await _get('/get_song', queryParams: {'videoId': songId});
      // Tenta extrair o ano do campo 'year' ou 'publishedDate'
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
      // Se veio dados, consideramos que é uma música válida
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
  // 11. GET LYRICS - não suportado, retorna vazio
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
  // 13. GET SEARCH SUGGESTIONS - não temos, retornamos vazio
  // ------------------------------------------------------------------
  Future<List<String>> getSearchSuggestion(String queryStr) async {
    printINFO("⚠️ getSearchSuggestion não suportado pelo proxy.");
    return [];
  }

  // ============================================================
  //  FUNÇÕES AUXILIARES DE FORMATAÇÃO (para compatibilidade)
  // ============================================================

  /// Categoriza os resultados da busca para o formato que as telas esperam
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
          // Fallback
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

  /// Formata dados de playlist para o formato esperado pelo app
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

  /// Formata dados de álbum
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

  /// Extrai uma única faixa do retorno de /get_song
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

  /// Calcula duração total de uma lista de faixas
  int _sumTotalDuration(List<dynamic> tracks) {
    int total = 0;
    for (var track in tracks) {
      if (track is Map && track.containsKey('duration')) {
        final dur = track['duration'];
        if (dur is int) total += dur;
        else if (dur is String) {
          // Tenta parsear se for string
          try {
            total += int.parse(dur);
          } catch (_) {}
        }
      }
    }
    return total;
  }
}
