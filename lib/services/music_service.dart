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
  //  CONFIGURAÇÃO DO PROXY (FALLBACK)
  // ============================================================
  static const String _proxyBaseUrl =
      'https://yt-proxy-music-production.up.railway.app';

  // ============================================================
  //  INSTÂNCIA DO PACOTE YT_FLUTTER_MUSICAPI
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
    printINFO("🎵 MusicServices inicializado. Proxy fallback: $_proxyBaseUrl");
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
  //  MÉTODO PARA REQUISIÇÕES AO PROXY (FALLBACK)
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
  // 1. SEARCH - tenta YtApi, fallback proxy
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> search(
    String query, {
    String? filter,
    String? scope,
    int limit = 30,
    bool ignoreSpelling = false,
    String? filterParams,
  }) async {
    // Primeiro tenta o YtApi
    if (_ytApiReady) {
      try {
        printINFO("🔍 Buscando com YtFlutterMusicapi: '$query'");
        final response = await _ytApi.searchMusic(query: query, limit: limit);
        if (response.success && response.data != null && response.data!.isNotEmpty) {
          printINFO("📊 YtApi retornou ${response.data!.length} resultados");
          return _categorizeYtResults(response.data!);
        } else {
          printINFO("⚠️ YtApi sem resultados: ${response.error ?? response.message ?? 'vazio'}");
        }
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
  // 2. GET HOME - usa YtApi (se disponível)
  // ------------------------------------------------------------------
  Future<dynamic> getHome({int limit = 4}) async {
    // YtFlutterMusicapi 3.4.4 não expõe feed de Home (sem getHome()).
    // Usa só o fallback proxy (se/quando existir endpoint /home).
    printINFO("⚠️ getHome via proxy não implementado. Retornando lista vazia.");
    return [];
  }

  // ------------------------------------------------------------------
  // 3. GET CHARTS - usa YtApi
  // ------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getCharts(String category,
      {String? countryCode}) async {
    if (!_ytApiReady) {
      printINFO("⚠️ YtApi não disponível. Retornando vazio.");
      return [];
    }
    try {
      printINFO("📈 Buscando charts: $category via YtApi (país: ${countryCode ?? 'BR'})");
      final response = await _ytApi.getCharts(country: countryCode ?? 'BR');
      if (!response.success || response.data == null || response.data!.isEmpty) {
        printINFO("⚠️ YtApi getCharts sem resultados: ${response.error ?? response.message ?? 'vazio'}");
        return [];
      }

      final chartSection = {
        'title': category,
        'contents': response.data!.map((e) => _convertYtChartItem(e)).toList(),
      };
      return [chartSection];
    } catch (e) {
      printERROR("❌ Erro no getCharts: $e");
      return [];
    }
  }

  // ------------------------------------------------------------------
  // 4. GET WATCH PLAYLIST - usa YtApi ou proxy
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
    // YtFlutterMusicapi 3.4.4 não tem getSong(id) nem getPlaylist(id).
    // Vai direto para o fallback proxy.

    // Fallback para proxy
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
    } catch (e) {
      printERROR("Erro no getWatchPlaylist via proxy: $e");
    }

    return {'tracks': [], 'playlistId': '', 'lyrics': null, 'related': null, 'additionalParamsForNext': null};
  }

  // ------------------------------------------------------------------
  // 5. GET PLAYLIST OR ALBUM SONGS - usa YtApi ou proxy
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getPlaylistOrAlbumSongs({
    String? playlistId,
    String? albumId,
    int limit = 3000,
    bool related = false,
    int suggestionsLimit = 0,
  }) async {
    // YtFlutterMusicapi 3.4.4 não tem getPlaylist(id) nem getAlbum(id).
    // Vai direto para o fallback proxy.

    // Fallback para proxy
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
    } catch (e) {
      printERROR("Erro no getPlaylistOrAlbumSongs via proxy: $e");
    }

    return {};
  }

  // ------------------------------------------------------------------
  // 6. GET ARTIST - usa YtApi
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getArtist(String artistId) async {
    // YtFlutterMusicapi 3.4.4 não tem getArtist(id) (só getArtistSongs por nome).
    // Fallback stub
    printINFO("⚠️ Retornando stub para artista.");
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
  // 7. GET ARTIST RELATED CONTENT - usa YtApi com search
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getArtistRelatedContent(
    String artistId,
    String tabName, {
    int limit = 10,
    Map<String, dynamic>? additionalParams,
  }) async {
    if (!_ytApiReady) {
      printINFO("⚠️ YtApi não disponível. Retornando vazio.");
      return {'contents': [], 'additionalParams': {}};
    }
    try {
      final response =
          await _ytApi.searchMusic(query: '$artistId $tabName', limit: limit);
      if (!response.success || response.data == null) {
        printINFO("⚠️ getArtistRelatedContent sem resultados: ${response.error ?? response.message ?? 'vazio'}");
        return {'contents': [], 'additionalParams': {}};
      }
      return {
        'contents': response.data!.map((e) => e.toMap()).toList(),
        'additionalParams': {},
      };
    } catch (e) {
      printERROR("Erro no getArtistRelatedContent: $e");
      return {'contents': [], 'additionalParams': {}};
    }
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
  // 8. GET SEARCH CONTINUATION - não suportado
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getSearchContinuation(
    Map<String, dynamic> continuationParams, {
    int limit = 10,
  }) async {
    printINFO("⚠️ getSearchContinuation não suportado.");
    return {};
  }

  // ------------------------------------------------------------------
  // 9. GET SONG YEAR - via YtApi
  // ------------------------------------------------------------------
  Future<String> getSongYear(String songId) async {
    // YtFlutterMusicapi 3.4.4 não tem getSong(id). Vai direto pro fallback proxy.
    // Fallback
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
  // 10. GET SONG WITH ID - via YtApi
  // ------------------------------------------------------------------
  Future<List> getSongWithId(String songId) async {
    // YtFlutterMusicapi 3.4.4 não tem getSong(id). Vai direto pro fallback proxy.
    // Fallback proxy
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
  // YtFlutterMusicapi 3.4.4 só devolve músicas na busca (sem campo 'type'
  // e sem álbum/artista/playlist), então tudo cai em 'Songs'.
  Map<String, dynamic> _categorizeYtResults(List<SearchResult> results) {
    final categories = {
      'Songs': [],
    };

    for (final item in results) {
      try {
        categories['Songs']!.add(_convertYtSong(item));
      } catch (e) {
        printERROR("Erro ao converter item YtApi: $e");
      }
    }

    categories.removeWhere((key, value) => value.isEmpty);
    return categories;
  }

  Map<String, dynamic> _convertYtSong(SearchResult r) {
    return {
      'videoId': r.videoId,
      'title': r.title,
      'artists': r.artists,
      'album': {},
      'thumbnails': r.albumArt != null ? [{'url': r.albumArt}] : [],
      'duration': r.duration ?? 0,
      'year': r.year ?? '',
      'playlistId': '',
      'audioUrl': r.audioUrl ?? '',
      'resultType': 'song',
    };
  }

  Map<String, dynamic> _convertYtChartItem(ChartItem c) {
    return {
      'videoId': c.videoId,
      'title': c.title,
      'artists': c.artists,
      'album': c.album ?? {},
      'thumbnails': c.albumArt != null ? [{'url': c.albumArt}] : [],
      'duration': c.duration ?? 0,
      'year': '',
      'playlistId': c.playlistId ?? '',
      'audioUrl': c.audioUrl ?? '',
      'rank': c.rank ?? '',
      'chartType': c.chartType,
      'resultType': 'song',
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
