// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart' as getx;
import 'package:hive/hive.dart';

import '../utils/helper.dart';
import 'constant.dart';
import 'youtube_music_api.dart';

// ============================================================
//  NetworkError
// ============================================================
class NetworkError implements Exception {
  final String message;
  NetworkError([this.message = "Network error occurred"]);
  @override
  String toString() => message;
}

class MusicServices extends getx.GetxService {
  final YouTubeMusicApi _api = YouTubeMusicApi();

  @override
  void onInit() {
    super.onInit();
    printINFO("🎵 MusicServices inicializado com YouTube Music API direta");
  }

  set hlCode(String code) {
    _api.hlCode = code;
  }

  // ============================================================
  //  1. SEARCH
  // ============================================================
  Future<Map<String, dynamic>> search(
    String query, {
    String? filter,
    String? scope,
    int limit = 30,
    bool ignoreSpelling = false,
    String? filterParams,
  }) async {
    try {
      printINFO("🔍 Buscando: '$query' (limit: $limit)");
      final raw = await _api.search(query, limit: limit);
      // O parse da resposta pode ser feito aqui ou em um parser separado
      // Por enquanto, retornamos os dados crus (como fazia o proxy)
      // Você pode usar o mesmo _categorizeSearchResults do proxy
      return _categorizeSearchResults(raw);
    } catch (e) {
      printERROR("❌ Erro no search: $e");
      return {};
    }
  }

  // ============================================================
  //  2. GET HOME (browseId = FEmusic_home)
  // ============================================================
  Future<dynamic> getHome({int limit = 4}) async {
    try {
      printINFO("🏠 Buscando Home...");
      final raw = await _api.browse('FEmusic_home');
      // Parse da home (extrair seções)
      return _parseHome(raw);
    } catch (e) {
      printERROR("❌ Erro no getHome: $e");
      return [];
    }
  }

  // ============================================================
  //  3. GET CHARTS (browseId = FEmusic_charts)
  // ============================================================
  Future<List<Map<String, dynamic>>> getCharts(String category,
      {String? countryCode}) async {
    try {
      printINFO("📈 Buscando charts: $category");
      final raw = await _api.browse('FEmusic_charts');
      // Parse dos charts
      return _parseCharts(raw, category);
    } catch (e) {
      printERROR("❌ Erro no getCharts: $e");
      return [];
    }
  }

  // ============================================================
  //  4. GET WATCH PLAYLIST (via /next)
  // ============================================================
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
      if (videoId.isEmpty) {
        // Se não tiver videoId, tenta usar playlistId (mas /next exige videoId)
        // Você pode adaptar: se tiver playlistId, buscar a primeira música da playlist
        if (playlistId != null) {
          // Obtém a playlist via browse e pega o primeiro vídeo
          final playlistData = await getPlaylistOrAlbumSongs(playlistId: playlistId);
          final tracks = playlistData['tracks'] as List? ?? [];
          if (tracks.isNotEmpty) {
            final first = tracks.first;
            if (first is Map && first.containsKey('videoId')) {
              videoId = first['videoId'].toString();
            }
          }
        }
        if (videoId.isEmpty) {
          return {'tracks': [], 'playlistId': playlistId ?? '', 'lyrics': null, 'related': null, 'additionalParamsForNext': null};
        }
      }

      printINFO("🎵 Obtendo watch playlist para: $videoId");
      final raw = await _api.next(
        videoId: videoId,
        playlistId: playlistId,
        radio: radio,
        shuffle: shuffle,
      );
      // Parse da watch playlist
      return _parseWatchPlaylist(raw);
    } catch (e) {
      printERROR("❌ Erro no getWatchPlaylist: $e");
      return {'tracks': [], 'playlistId': '', 'lyrics': null, 'related': null, 'additionalParamsForNext': null};
    }
  }

  // ============================================================
  //  5. GET PLAYLIST OR ALBUM SONGS (via /browse)
  // ============================================================
  Future<Map<String, dynamic>> getPlaylistOrAlbumSongs({
    String? playlistId,
    String? albumId,
    int limit = 3000,
    bool related = false,
    int suggestionsLimit = 0,
  }) async {
    try {
      if (playlistId != null) {
        printINFO("📋 Obtendo playlist: $playlistId");
        final browseId = playlistId.startsWith('VL') ? playlistId : 'VL$playlistId';
        final raw = await _api.browse(browseId);
        return _parsePlaylist(raw);
      } else if (albumId != null) {
        printINFO("📀 Obtendo álbum: $albumId");
        final raw = await _api.browse(albumId);
        return _parseAlbum(raw);
      }
      return {};
    } catch (e) {
      printERROR("❌ Erro no getPlaylistOrAlbumSongs: $e");
      return {};
    }
  }

  // ============================================================
  //  6. GET ARTIST (via /browse)
  // ============================================================
  Future<Map<String, dynamic>> getArtist(String artistId) async {
    try {
      printINFO("🎤 Obtendo artista: $artistId");
      final raw = await _api.browse(artistId);
      return _parseArtist(raw);
    } catch (e) {
      printERROR("❌ Erro no getArtist: $e");
      return {
        'id': artistId,
        'name': 'Unknown',
        'thumbnails': [],
        'description': '',
        'subscribers': '0',
        'radioId': '',
      };
    }
  }

  // ============================================================
  //  7. GET ARTIST RELATED CONTENT (via /browse com params)
  // ============================================================
  Future<Map<String, dynamic>> getArtistRelatedContent(
    String artistId,
    String tabName, {
    int limit = 10,
    Map<String, dynamic>? additionalParams,
  }) async {
    try {
      printINFO("🎤 Buscando conteúdo relacionado para: $artistId, tab: $tabName");
      // Exemplo de params para abas de artista (songs, albums, etc.)
      final params = _getArtistTabParams(tabName);
      final raw = await _api.browse(artistId, params: params);
      // Parse da seção
      return _parseArtistSection(raw, tabName);
    } catch (e) {
      printERROR("❌ Erro no getArtistRelatedContent: $e");
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

  // ============================================================
  //  8. GET SONG YEAR (via /player)
  // ============================================================
  Future<String> getSongYear(String songId) async {
    try {
      final raw = await _api.player(songId);
      // Extrair ano do microformat ou publishedDate
      final microformat = raw['microformat']?['microformatDataRenderer'];
      final date = microformat?['publishedDate'] ?? '';
      if (date is String && date.isNotEmpty) {
        final match = RegExp(r'\d{4}').firstMatch(date);
        return match?.group(0) ?? DateTime.now().year.toString();
      }
    } catch (_) {}
    return DateTime.now().year.toString();
  }

  // ============================================================
  //  9. GET SONG WITH ID (via /player)
  // ============================================================
  Future<List> getSongWithId(String songId) async {
    try {
      final raw = await _api.player(songId);
      final track = _extractTrackFromPlayer(raw);
      if (track.isNotEmpty) {
        return [true, [track]];
      }
    } catch (_) {}
    return [false, null];
  }

  // ============================================================
  //  OUTROS MÉTODOS (stubs)
  // ============================================================
  dynamic getLyrics(String browseId) {
    printINFO("⚠️ getLyrics não suportado diretamente.");
    return '';
  }

  dynamic getContentRelatedToSong(String videoId, String hlCode) {
    printINFO("⚠️ getContentRelatedToSong não suportado.");
    return [];
  }

  Future<List<String>> getSearchSuggestion(String queryStr) async {
    printINFO("⚠️ getSearchSuggestion não suportado.");
    return [];
  }

  Future<Map<String, dynamic>> getSearchContinuation(
    Map<String, dynamic> continuationParams, {
    int limit = 10,
  }) async {
    printINFO("⚠️ getSearchContinuation não suportado.");
    return {};
  }

  // ============================================================
  //  FUNÇÕES DE PARSE (a implementar)
  // ============================================================
  // Você pode reutilizar as funções de parse do seu antigo código
  // ou adaptar conforme a estrutura da resposta do YouTube.

  Map<String, dynamic> _categorizeSearchResults(Map<String, dynamic> raw) {
    // Implementar extração de categorias (Songs, Videos, etc.)
    // Baseado na resposta /search
    // ...
    return {};
  }

  List<dynamic> _parseHome(Map<String, dynamic> raw) {
    // Extrair seções da home
    // ...
    return [];
  }

  List<Map<String, dynamic>> _parseCharts(Map<String, dynamic> raw, String category) {
    // Extrair charts
    // ...
    return [];
  }

  Map<String, dynamic> _parseWatchPlaylist(Map<String, dynamic> raw) {
    // Extrair tracks da watch playlist
    // ...
    return {'tracks': [], 'playlistId': '', 'lyrics': null, 'related': null, 'additionalParamsForNext': null};
  }

  Map<String, dynamic> _parsePlaylist(Map<String, dynamic> raw) {
    // Extrair playlist detalhada
    // ...
    return {};
  }

  Map<String, dynamic> _parseAlbum(Map<String, dynamic> raw) {
    // Extrair álbum detalhado
    // ...
    return {};
  }

  Map<String, dynamic> _parseArtist(Map<String, dynamic> raw) {
    // Extrair artista
    // ...
    return {
      'id': '',
      'name': '',
      'thumbnails': [],
      'description': '',
      'subscribers': '0',
      'radioId': '',
    };
  }

  Map<String, dynamic> _parseArtistSection(Map<String, dynamic> raw, String tabName) {
    // Extrair seção do artista
    // ...
    return {'contents': [], 'additionalParams': {}};
  }

  Map<String, dynamic> _extractTrackFromPlayer(Map<String, dynamic> raw) {
    // Extrair track do /player
    // ...
    return {};
  }

  Map<String, dynamic>? _getArtistTabParams(String tabName) {
    // Retornar params para abas de artista
    return null;
  }
}
