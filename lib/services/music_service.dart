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
  //  CONFIGURAÇÃO DO PROXY (fallback)
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
  //  MÉTODOS PARA O PROXY (FALLBACK)
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
        // O método correto é search(query) - sem argumentos nomeados
        final results = await _ytApi.search(query);
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
  // 2. GET HOME - usa YtApi
  // ------------------------------------------------------------------
  Future<dynamic> getHome({int limit = 4}) async {
    if (!_ytApiReady) {
      printINFO("⚠️ YtApi não disponível. Retornando lista vazia.");
      return [];
    }
    try {
      printINFO("🏠 Buscando Home do YouTube Music...");
      final homeData = await _ytApi.getHome();
      printINFO("📊 Home retornou ${homeData.length} seções");
      
      final List<Map<String, dynamic>> parsedHome = [];
      for (var section in homeData) {
        try {
          // Assume que cada seção tem 'title' e 'items' (lista de Music)
          final items = (section.items as List).map((item) => item.toJson()).toList();
          if (items.isNotEmpty) {
            parsedHome.add({
              'title': section.title,
              'contents': items,
            });
          }
        } catch (e) {
          printERROR("Erro ao parsear seção: $e");
        }
      }
      return parsedHome;
    } catch (e) {
      printERROR("❌ Erro no getHome: $e");
      return [];
    }
  }

  // ------------------------------------------------------------------
  // 3. GET CHARTS - usa YtApi com search
  // ------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getCharts(String category,
      {String? countryCode}) async {
    if (!_ytApiReady) {
      printINFO("⚠️ YtApi não disponível. Retornando vazio.");
      return [];
    }
    try {
      printINFO("📈 Buscando charts: $category");
      final results = await _ytApi.search(category);
      if (results.isEmpty) return [];
      
      final chartSection = {
        'title': category,
        'contents': results.map((e) => e.toJson()).toList(),
      };
      return [chartSection];
    } catch (e) {
      printERROR("❌ Erro no getCharts: $e");
      return [];
    }
  }

  // ------------------------------------------------------------------
  // 4. GET WATCH PLAYLIST - usa YtApi
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
      if (videoId.isNotEmpty && _ytApiReady) {
        printINFO("🎵 Obtendo música: $videoId via YtApi");
        final song = await _ytApi.getSong(videoId);
        final track = _extractTrackFromYtSong(song);
        return {
          'tracks': [track],
          'playlistId': playlistId ?? '',
          'lyrics': null,
          'related': null,
          'additionalParamsForNext': null,
        };
      } else if (playlistId != null && _ytApiReady) {
        printINFO("📋 Obtendo playlist: $playlistId via YtApi");
        final playlist = await _ytApi.getPlaylist(playlistId);
        final tracks = playlist.songs.map((e) => _extractTrackFromYtSong(e)).toList();
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
      printERROR("Erro no getWatchPlaylist via YtApi: $e");
      // Fallback para proxy
      try {
        return await _getWatchPlaylistProxy(videoId, playlistId);
      } catch (_) {
        return {'tracks': [], 'playlistId': '', 'lyrics': null, 'related': null, 'additionalParamsForNext': null};
      }
    }
  }

  Future<Map<String, dynamic>> _getWatchPlaylistProxy(String videoId, String? playlistId) async {
    try {
      if (videoId.isNotEmpty) {
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

  // ------------------------------------------------------------------
  // 5. GET PLAYLIST OR ALBUM SONGS - usa YtApi
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getPlaylistOrAlbumSongs({
    String? playlistId,
    String? albumId,
    int limit = 3000,
    bool related = false,
    int suggestionsLimit = 0,
  }) async {
    try {
      if (playlistId != null && _ytApiReady) {
        printINFO("📋 Obtendo playlist: $playlistId via YtApi");
        final playlist = await _ytApi.getPlaylist(playlistId);
        return _formatYtPlaylist(playlist);
      } else if (albumId != null && _ytApiReady) {
        printINFO("📀 Obtendo álbum: $albumId via YtApi");
        final album = await _ytApi.getAlbum(albumId);
        return _formatYtAlbum(album);
      }
      return {};
    } catch (e) {
      printERROR("Erro no getPlaylistOrAlbumSongs via YtApi: $e");
      // Fallback para proxy
      try {
        return await _getPlaylistOrAlbumProxy(playlistId, albumId);
      } catch (_) {
        return {};
      }
    }
  }

  Future<Map<String, dynamic>> _getPlaylistOrAlbumProxy(String? playlistId, String? albumId) async {
    try {
      if (playlistId != null) {
        final data = await _get('/get_playlist', queryParams: {'playlistId': playlistId});
        return _formatPlaylistData(data);
      } else if (albumId != null) {
        final data = await _get('/get_album', queryParams: {'browseId': albumId});
        return _formatAlbumData(data);
      }
    } catch (_) {}
    return {};
  }

  // ------------------------------------------------------------------
  // 6. GET ARTIST - usa YtApi
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getArtist(String artistId) async {
    if (_ytApiReady) {
      try {
        printINFO("🎤 Obtendo artista: $artistId via YtApi");
        final artist = await _ytApi.getArtist(artistId);
        return {
          'id': artistId,
          'name': artist.name,
          'thumbnails': artist.thumbnails.isNotEmpty
              ? artist.thumbnails.map((e) => {'url': e.url}).toList()
              : [],
          'description': artist.description ?? '',
          'subscribers': artist.subscribers?.toString() ?? '0',
          'radioId': '',
        };
      } catch (e) {
        printERROR("Erro no getArtist via YtApi: $e");
      }
    }
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
      final results = await _ytApi.search('$artistId $tabName');
      return {
        'contents': results.map((e) => e.toJson()).toList(),
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
    if (_ytApiReady) {
      try {
        final song = await _ytApi.getSong(songId);
        return song.year?.toString() ?? DateTime.now().year.toString();
      } catch (_) {}
    }
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
    if (_ytApiReady) {
      try {
        final song = await _ytApi.getSong(songId);
        final track = _extractTrackFromYtSong(song);
        return [true, [track]];
      } catch (_) {}
    }
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

  // --- Conversão dos resultados do proxy ---
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

  // --- Conversão dos resultados do YtFlutterMusicapi ---
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

  Map<String, dynamic> _extractTrackFromYtSong(dynamic song) {
    try {
      final json = song.toJson();
      return _convertYtSong(json);
    } catch (e) {
      return {};
    }
  }

  Map<String, dynamic> _formatYtPlaylist(dynamic playlist) {
    try {
      final json = playlist.toJson();
      return {
        'id': json['id'] ?? '',
        'title': json['title'] ?? '',
        'thumbnails': json['thumbnails'] ?? [],
        'description': json['description'] ?? '',
        'trackCount': json['trackCount'] ?? 0,
        'duration': json['duration'] ?? '',
        'tracks': json['songs']?.map((e) => _extractTrackFromYtSong(e)).toList() ?? [],
        'author': json['author'] ?? {},
        'year': json['year'] ?? '',
        'duration_seconds': 0,
      };
    } catch (e) {
      return {};
    }
  }

  Map<String, dynamic> _formatYtAlbum(dynamic album) {
    try {
      final json = album.toJson();
      return {
        'id': json['id'] ?? '',
        'title': json['title'] ?? '',
        'thumbnails': json['thumbnails'] ?? [],
        'description': json['description'] ?? '',
        'trackCount': json['trackCount'] ?? 0,
        'tracks': json['songs']?.map((e) => _extractTrackFromYtSong(e)).toList() ?? [],
        'artists': json['artists'] ?? [],
        'year': json['year'] ?? '',
        'duration_seconds': 0,
        'other_versions': [],
      };
    } catch (e) {
      return {};
    }
  }

  // ------------------------------------------------------------------
  //  FUNÇÕES DE FORMATAÇÃO (para compatibilidade com métodos antigos)
  // ------------------------------------------------------------------
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
