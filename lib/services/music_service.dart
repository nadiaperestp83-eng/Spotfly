// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart' as getx;
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'youtube_music_api.dart';

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
  //  CONFIGURAÇÃO DO PROXY (fallback) - PORTA 8080
  // ============================================================
  static const String _proxyBaseUrl =
      'https://yt-proxy-music-production.up.railway.app:8080';

  // ============================================================
  //  CLIENTE DA API DO YOUTUBE MUSIC
  // ============================================================
  final YouTubeMusicApi _ytApi = YouTubeMusicApi();

  // ============================================================
  //  INICIALIZAÇÃO
  // ============================================================
  @override
  void onInit() {
    super.onInit();
    printINFO("🎵 MusicServices inicializado com YouTubeMusicApi + proxy fallback");
  }

  set hlCode(String code) {
    printINFO("hlCode set to: $code (ignorado)");
  }

  // ============================================================
  //  MÉTODO PRIVADO PARA REQUISIÇÕES AO PROXY (fallback)
  // ============================================================
  Future<dynamic> _get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    try {
      final uri = Uri.parse('$_proxyBaseUrl$endpoint')
          .replace(queryParameters: queryParams?.map((k, v) => MapEntry(k, v.toString())));
      
      printINFO("📡 GET $uri (proxy fallback)");
      
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
  // 1. SEARCH - usa YouTubeMusicApi (com fallback proxy)
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
      printINFO("🔍 Buscando via YouTubeMusicApi: '$query'");
      final result = await _ytApi.search(query);
      if (result.isNotEmpty) {
        printINFO("📊 YouTubeMusicApi retornou ${result.keys.length} categorias");
        return result;
      } else {
        printINFO("⚠️ YouTubeMusicApi retornou vazio. Tentando proxy...");
      }
    } catch (e) {
      printINFO("⚠️ YouTubeMusicApi falhou: $e. Tentando proxy...");
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
          return _categorizeProxyResults(results);
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
  // 2. GET HOME - usa YouTubeMusicApi (com fallback proxy)
  // ------------------------------------------------------------------
  Future<dynamic> getHome({int limit = 4}) async {
    try {
      printINFO("🏠 Buscando Home via YouTubeMusicApi...");
      final homeData = await _ytApi.getHome();
      if (homeData.isNotEmpty) {
        printINFO("📊 Home retornou ${homeData.length} seções");
        return homeData;
      }
      printINFO("⚠️ YouTubeMusicApi retornou vazio. Tentando proxy...");
    } catch (e) {
      printINFO("⚠️ YouTubeMusicApi falhou: $e. Tentando proxy...");
    }

    // Fallback para proxy (se tiver /home)
    printINFO("⚠️ getHome via proxy não implementado. Retornando lista vazia.");
    return [];
  }

  // ------------------------------------------------------------------
  // 3. GET CHARTS - ainda não implementado
  // ------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getCharts(String category,
      {String? countryCode}) async {
    printINFO("⚠️ getCharts não implementado. Retornando vazio.");
    return [];
  }

  // ------------------------------------------------------------------
  // 4. GET WATCH PLAYLIST - usa proxy (ou YouTubeMusicApi)
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
        printINFO("🎵 Obtendo música: $videoId via YouTubeMusicApi");
        final data = await _ytApi.getSong(videoId);
        final track = _extractTrackFromYT(data);
        return {
          'tracks': [track],
          'playlistId': playlistId ?? '',
          'lyrics': null,
          'related': null,
          'additionalParamsForNext': null,
        };
      } else if (playlistId != null) {
        printINFO("📋 Obtendo playlist: $playlistId via YouTubeMusicApi");
        final data = await _ytApi.getPlaylist(playlistId);
        final tracks = _parseTracksFromPlaylist(data);
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
      printERROR("Erro no getWatchPlaylist via YouTubeMusicApi: $e");
      // Fallback para proxy
      try {
        if (videoId.isNotEmpty) {
          final data = await _get('/get_song', queryParams: {'videoId': videoId});
          final track = _extractTrackFromProxy(data);
          return {
            'tracks': [track],
            'playlistId': playlistId ?? '',
            'lyrics': null,
            'related': null,
            'additionalParamsForNext': null,
          };
        } else if (playlistId != null) {
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
      } catch (_) {}
      return {'tracks': [], 'playlistId': '', 'lyrics': null, 'related': null, 'additionalParamsForNext': null};
    }
  }

  // ------------------------------------------------------------------
  // 5. GET PLAYLIST OR ALBUM SONGS - usa YouTubeMusicApi
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
        printINFO("📋 Obtendo playlist: $playlistId via YouTubeMusicApi");
        final data = await _ytApi.getPlaylist(playlistId);
        return _formatPlaylistFromYT(data);
      } else if (albumId != null) {
        printINFO("📀 Obtendo álbum: $albumId via YouTubeMusicApi");
        final data = await _ytApi.getAlbum(albumId);
        return _formatAlbumFromYT(data);
      }
      return {};
    } catch (e) {
      printERROR("Erro no getPlaylistOrAlbumSongs via YouTubeMusicApi: $e");
      // Fallback proxy
      try {
        if (playlistId != null) {
          final data = await _get('/get_playlist', queryParams: {'playlistId': playlistId});
          return _formatPlaylistFromProxy(data);
        } else if (albumId != null) {
          final data = await _get('/get_album', queryParams: {'browseId': albumId});
          return _formatAlbumFromProxy(data);
        }
      } catch (_) {}
      return {};
    }
  }

  // ------------------------------------------------------------------
  // 6. GET ARTIST - stub (não implementado)
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getArtist(String artistId) async {
    printINFO("⚠️ getArtist não implementado. Retornando stub.");
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
    printINFO("⚠️ getArtistRelatedContent não implementado.");
    return {
      'contents': [],
      'additionalParams': {},
    };
  }

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
    printINFO("⚠️ getSearchContinuation não implementado.");
    return {};
  }

  // ------------------------------------------------------------------
  // 9. GET SONG YEAR - via YouTubeMusicApi
  // ------------------------------------------------------------------
  Future<String> getSongYear(String songId) async {
    try {
      final data = await _ytApi.getSong(songId);
      final year = data['microformat']?['microformatDataRenderer']?['publishedDate'] ?? '';
      if (year is String && year.isNotEmpty) {
        final match = RegExp(r'\d{4}').firstMatch(year);
        return match?.group(0) ?? DateTime.now().year.toString();
      }
    } catch (_) {}
    return DateTime.now().year.toString();
  }

  // ------------------------------------------------------------------
  // 10. GET SONG WITH ID - via YouTubeMusicApi
  // ------------------------------------------------------------------
  Future<List> getSongWithId(String songId) async {
    try {
      final data = await _ytApi.getSong(songId);
      final track = _extractTrackFromYT(data);
      return [true, [track]];
    } catch (_) {}
    return [false, null];
  }

  // ------------------------------------------------------------------
  // 11. GET LYRICS - não implementado
  // ------------------------------------------------------------------
  dynamic getLyrics(String browseId) {
    printINFO("⚠️ getLyrics não implementado.");
    return '';
  }

  // ------------------------------------------------------------------
  // 12. GET CONTENT RELATED TO SONG - stub
  // ------------------------------------------------------------------
  dynamic getContentRelatedToSong(String videoId, String hlCode) {
    printINFO("⚠️ getContentRelatedToSong não implementado.");
    return [];
  }

  // ------------------------------------------------------------------
  // 13. GET SEARCH SUGGESTIONS - stub
  // ------------------------------------------------------------------
  Future<List<String>> getSearchSuggestion(String queryStr) async {
    printINFO("⚠️ getSearchSuggestion não implementado.");
    return [];
  }

  // ============================================================
  //  FUNÇÕES AUXILIARES DE CONVERSÃO (PROXY)
  // ============================================================

  Map<String, dynamic> _categorizeProxyResults(List<dynamic> results) {
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
        case 'song': case 'track': categories['Songs']!.add(item); break;
        case 'video': categories['Videos']!.add(item); break;
        case 'album': categories['Albums']!.add(item); break;
        case 'artist': case 'channel': categories['Artists']!.add(item); break;
        case 'playlist':
          if (title.toLowerCase().contains('community') || id.contains('community')) {
            categories['Community playlists']!.add(item);
          } else {
            categories['Featured playlists']!.add(item);
          }
          break;
        default:
          if (item.containsKey('videoId') && item.containsKey('title')) categories['Songs']!.add(item);
          else if (item.containsKey('browseId') && item.containsKey('trackCount')) categories['Albums']!.add(item);
          else if (item.containsKey('playlistId')) categories['Featured playlists']!.add(item);
      }
    }
    categories.removeWhere((key, value) => value.isEmpty);
    return categories;
  }

  Map<String, dynamic> _extractTrackFromProxy(Map<String, dynamic> data) {
    return {
      'videoId': data['videoId'] ?? '',
      'title': data['title'] ?? '',
      'artists': data['artists'] ?? [],
      'album': data['album'] ?? {},
      'thumbnails': data['thumbnails'] ?? [],
      'duration': data['duration'] ?? 0,
      'year': data['year'] ?? '',
      'playlistId': data['playlistId'] ?? '',
    };
  }

  Map<String, dynamic> _formatPlaylistFromProxy(Map<String, dynamic> data) {
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

  Map<String, dynamic> _formatAlbumFromProxy(Map<String, dynamic> data) {
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

  // ============================================================
  //  FUNÇÕES AUXILIARES DE CONVERSÃO (YouTubeMusicApi)
  // ============================================================

  Map<String, dynamic> _extractTrackFromYT(Map<String, dynamic> data) {
    try {
      final videoDetails = data['videoDetails'] ?? {};
      return {
        'videoId': videoDetails['videoId'] ?? '',
        'title': videoDetails['title'] ?? '',
        'artists': videoDetails['author'] != null ? [{'name': videoDetails['author']}] : [],
        'album': {},
        'thumbnails': videoDetails['thumbnail']?['thumbnails'] ?? [],
        'duration': int.tryParse(videoDetails['lengthSeconds']?.toString() ?? '0') ?? 0,
        'year': '',
        'playlistId': '',
      };
    } catch (_) {
      return {};
    }
  }

  List<dynamic> _parseTracksFromPlaylist(Map<String, dynamic> data) {
    final List<dynamic> tracks = [];
    try {
      final contents = data['contents']
          ?['twoColumnBrowseResultsRenderer']
          ?['tabs']?[0]
          ?['tabRenderer']
          ?['content']
          ?['sectionListRenderer']
          ?['contents']?[0]
          ?['musicPlaylistShelfRenderer']
          ?['contents'] as List?;
      if (contents == null) return tracks;
      for (var item in contents) {
        final renderer = item['musicResponsiveListItemRenderer'];
        if (renderer == null) continue;
        final track = {
          'videoId': renderer['playlistItemData']?['videoId'] ?? '',
          'title': renderer['flexColumns']?[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?[0]?['text'] ?? '',
          'artists': renderer['flexColumns']?[1]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?.map((run) => {'name': run['text']}).toList() ?? [],
          'duration': renderer['fixedColumns']?[0]?['musicResponsiveListItemFixedColumnRenderer']?['text']?['runs']?[0]?['text'] ?? '',
          'thumbnails': renderer['thumbnail']?['thumbnails'] ?? [],
        };
        if (track['videoId'].isNotEmpty) tracks.add(track);
      }
    } catch (e) {
      printERROR("Erro ao parsear tracks da playlist: $e");
    }
    return tracks;
  }

  Map<String, dynamic> _formatPlaylistFromYT(Map<String, dynamic> data) {
    final playlist = {
      'id': data['contents']?['twoColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']?[0]?['musicPlaylistShelfRenderer']?['playlistId'] ?? '',
      'title': '',
      'thumbnails': [],
      'description': '',
      'trackCount': 0,
      'duration': '',
      'tracks': _parseTracksFromPlaylist(data),
      'author': {},
      'year': '',
      'duration_seconds': 0,
    };
    try {
      final header = data['header']?['musicDetailHeaderRenderer'];
      if (header != null) {
        playlist['title'] = header['title']?['runs']?[0]?['text'] ?? '';
        playlist['thumbnails'] = header['thumbnail']?['thumbnails'] ?? [];
        playlist['description'] = header['description']?['runs']?[0]?['text'] ?? '';
        playlist['trackCount'] = int.tryParse(header['subtitle']?['runs']?[0]?['text']?.split(' ')?[0] ?? '0') ?? 0;
      }
    } catch (_) {}
    return playlist;
  }

  Map<String, dynamic> _formatAlbumFromYT(Map<String, dynamic> data) {
    final album = {
      'id': '',
      'title': '',
      'thumbnails': [],
      'description': '',
      'trackCount': 0,
      'tracks': [],
      'artists': [],
      'year': '',
      'duration_seconds': 0,
      'other_versions': [],
    };
    try {
      final header = data['header']?['musicDetailHeaderRenderer'];
      if (header != null) {
        album['title'] = header['title']?['runs']?[0]?['text'] ?? '';
        album['thumbnails'] = header['thumbnail']?['thumbnails'] ?? [];
        album['description'] = header['description']?['runs']?[0]?['text'] ?? '';
        album['year'] = header['subtitle']?['runs']?[3]?['text'] ?? '';
        album['artists'] = header['subtitle']?['runs']?[1]?['text'] ?? '';
      }
      final contents = data['contents']
          ?['twoColumnBrowseResultsRenderer']
          ?['secondaryContents']
          ?['sectionListRenderer']
          ?['contents']?[0]
          ?['musicShelfRenderer']
          ?['contents'] as List?;
      if (contents != null) {
        final tracks = [];
        for (var item in contents) {
          final renderer = item['musicResponsiveListItemRenderer'];
          if (renderer != null) {
            final track = {
              'videoId': renderer['playlistItemData']?['videoId'] ?? '',
              'title': renderer['flexColumns']?[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?[0]?['text'] ?? '',
              'duration': renderer['fixedColumns']?[0]?['musicResponsiveListItemFixedColumnRenderer']?['text']?['runs']?[0]?['text'] ?? '',
              'thumbnails': renderer['thumbnail']?['thumbnails'] ?? [],
            };
            if (track['videoId'].isNotEmpty) tracks.add(track);
          }
        }
        album['tracks'] = tracks;
        album['trackCount'] = tracks.length;
      }
    } catch (e) {
      printERROR("Erro ao parsear álbum: $e");
    }
    return album;
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
