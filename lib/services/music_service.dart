// ignore_for_file: constant_identifier_names

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart' as getx;
import 'package:hive/hive.dart';

import 'youtube_music_api.dart';
import 'stream_service.dart'; // já existe, para áudio
import '../models/album.dart';
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
  final YouTubeMusicApi _api = YouTubeMusicApi();
  final StreamService _streamService = StreamService(); // se já existir

  // ============================================================
  //  INICIALIZAÇÃO
  // ============================================================
  @override
  void onInit() {
    super.onInit();
    printINFO("🎵 MusicServices inicializado com YouTubeMusicApi");
  }

  set hlCode(String code) {
    // A ser implementado se necessário
    printINFO("hlCode set to: $code");
  }

  // ============================================================
  //  MÉTODOS PÚBLICOS
  // ============================================================

  // ------------------------------------------------------------------
  // 1. SEARCH
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
      printINFO("🔍 Buscando: '$query'");
      final result = await _api.search(query, limit: limit);
      final results = result['contents']?['tabbedSearchResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'];
      // Aqui você deve extrair e categorizar os resultados manualmente,
      // ou usar um parser similar ao antigo nav_parser.dart.
      // Por simplicidade, vou retornar o JSON bruto por enquanto.
      // Você pode adaptar conforme a estrutura do seu app.
      printINFO("📊 Busca retornou dados");
      return result;
    } catch (e) {
      printERROR("❌ Erro no search: $e");
      return {};
    }
  }

  // ------------------------------------------------------------------
  // 2. GET HOME
  // ------------------------------------------------------------------
  Future<dynamic> getHome({int limit = 4}) async {
    try {
      printINFO("🏠 Buscando Home...");
      final result = await _api.browse('FEmusic_home');
      // Parse da resposta para extrair seções de música
      // Você pode usar uma versão simplificada do parseMixedContent aqui
      return _parseHomeContent(result);
    } catch (e) {
      printERROR("❌ Erro no getHome: $e");
      return [];
    }
  }

  List<dynamic> _parseHomeContent(Map<String, dynamic> data) {
    // Extrai as seções da Home – adapte conforme seu app
    final contents = data['contents']?['twoColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'];
    if (contents == null) return [];
    List result = [];
    for (var section in contents) {
      final shelf = section['musicCarouselShelfRenderer'];
      if (shelf != null) {
        final title = shelf['header']?['musicCarouselShelfBasicHeaderRenderer']?['title']?['runs']?[0]?['text'] ?? '';
        final items = shelf['contents'] ?? [];
        result.add({
          'title': title,
          'contents': items,
        });
      }
    }
    return result;
  }

  // ------------------------------------------------------------------
  // 3. GET CHARTS
  // ------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getCharts(String category,
      {String? countryCode}) async {
    try {
      printINFO("📈 Buscando charts: $category");
      final result = await _api.browse('FEmusic_charts',
          additionalData: countryCode != null
              ? {'formData': {'selectedValues': [countryCode]}}
              : null);
      // Parse simples
      final sections = result['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'];
      if (sections == null) return [];
      List<Map<String, dynamic>> charts = [];
      for (var section in sections) {
        final shelf = section['musicCarouselShelfRenderer'];
        if (shelf != null) {
          final title = shelf['header']?['musicCarouselShelfBasicHeaderRenderer']?['title']?['runs']?[0]?['text'] ?? '';
          final items = shelf['contents'] ?? [];
          if (title.contains('Video charts') || title.contains(category)) {
            charts.add({
              'title': title,
              'contents': items,
            });
          }
        }
      }
      return charts;
    } catch (e) {
      printERROR("❌ Erro no getCharts: $e");
      return [];
    }
  }

  // ------------------------------------------------------------------
  // 4. GET WATCH PLAYLIST
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
      // Usamos a API 'next'
      final result = await _api.next(videoId, playlistId: playlistId);
      // Extrai as faixas da playlist
      final tracks = _parseWatchPlaylist(result);
      return {
        'tracks': tracks,
        'playlistId': playlistId ?? '',
        'lyrics': null,
        'related': null,
        'additionalParamsForNext': null,
      };
    } catch (e) {
      printERROR("❌ Erro no getWatchPlaylist: $e");
      return {'tracks': [], 'playlistId': '', 'lyrics': null, 'related': null, 'additionalParamsForNext': null};
    }
  }

  List<dynamic> _parseWatchPlaylist(Map<String, dynamic> data) {
    // Extrai lista de faixas do watch playlist
    final contents = data['contents']?['singleColumnMusicWatchNextResultsRenderer']?['tabbedRenderer']?['watchNextTabbedResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['musicQueueRenderer']?['content']?['playlistPanelRenderer']?['contents'];
    if (contents == null) return [];
    List tracks = [];
    for (var item in contents) {
      final video = item['playlistPanelVideoRenderer'];
      if (video != null) {
        tracks.add({
          'videoId': video['videoId'],
          'title': video['title']?['runs']?[0]?['text'] ?? '',
          'artists': video['longBylineText']?['runs'] ?? [],
          'thumbnails': video['thumbnail']?['thumbnails'] ?? [],
          'duration': video['lengthText']?['simpleText'] ?? '0',
        });
      }
    }
    return tracks;
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
        final result = await _api.browse('VL$playlistId');
        return _parsePlaylist(result);
      } else if (albumId != null) {
        final result = await _api.browse(albumId);
        return _parseAlbum(result);
      }
      return {};
    } catch (e) {
      printERROR("❌ Erro no getPlaylistOrAlbumSongs: $e");
      return {};
    }
  }

  Map<String, dynamic> _parsePlaylist(Map<String, dynamic> data) {
    // Extrai informações da playlist
    final header = data['header']?['musicDetailHeaderRenderer'];
    final contents = data['contents']?['twoColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']?[0]?['musicPlaylistShelfRenderer']?['contents'];
    final tracks = contents.map((item) {
      final video = item['musicResponsiveListItemRenderer'];
      if (video == null) return null;
      return {
        'videoId': video['videoId'],
        'title': video['title']?['runs']?[0]?['text'] ?? '',
        'artists': video['longBylineText']?['runs'] ?? [],
        'thumbnails': video['thumbnail']?['thumbnails'] ?? [],
        'duration': video['lengthText']?['simpleText'] ?? '0',
      };
    }).where((t) => t != null).toList();
    return {
      'id': playlistId,
      'title': header?['title']?['runs']?[0]?['text'] ?? '',
      'thumbnails': header?['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] ?? [],
      'description': header?['description']?['runs']?[0]?['text'] ?? '',
      'trackCount': tracks.length,
      'tracks': tracks,
    };
  }

  Map<String, dynamic> _parseAlbum(Map<String, dynamic> data) {
    // Similar ao parsePlaylist
    // Você pode implementar conforme necessário
    return {};
  }

  // ------------------------------------------------------------------
  // 6. GET ARTIST
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getArtist(String artistId) async {
    try {
      final result = await _api.browse(artistId);
      final header = result['header']?['musicImmersiveHeaderRenderer'] ?? result['header']?['musicArtistHeaderRenderer'];
      return {
        'id': artistId,
        'name': header?['title']?['runs']?[0]?['text'] ?? 'Unknown',
        'thumbnails': header?['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] ?? [],
        'description': header?['description']?['runs']?[0]?['text'] ?? '',
        'subscribers': '0',
        'radioId': '',
      };
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

  // ------------------------------------------------------------------
  // 7. GET ARTIST RELATED CONTENT
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getArtistRelatedContent(
    String artistId,
    String tabName, {
    int limit = 10,
    Map<String, dynamic>? additionalParams,
  }) async {
    // Implementação simples: busca os álbuns/playlists do artista
    try {
      final result = await _api.browse(artistId);
      // Extrai dados da aba específica (Songs, Albums, Playlists)
      // Isso vai depender da estrutura do JSON
      return {
        'contents': [],
        'additionalParams': {},
      };
    } catch (e) {
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
  // 8. GET SEARCH CONTINUATION (scroll infinito)
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getSearchContinuation(
    Map<String, dynamic> continuationParams, {
    int limit = 10,
  }) async {
    // Reimplementar usando a API de continuations
    try {
      final response = await _api.search('', limit: 1); // placeholder
      return {};
    } catch (e) {
      return {};
    }
  }

  // ------------------------------------------------------------------
  // 9. GET SONG YEAR
  // ------------------------------------------------------------------
  Future<String> getSongYear(String songId) async {
    try {
      final result = await _api.player(songId);
      final microformat = result['microformat']?['microformatDataRenderer'];
      if (microformat != null) {
        final date = microformat['publishedDate'] ?? '';
        if (date is String) {
          final match = RegExp(r'\d{4}').firstMatch(date);
          return match?.group(0) ?? DateTime.now().year.toString();
        }
      }
    } catch (_) {}
    return DateTime.now().year.toString();
  }

  // ------------------------------------------------------------------
  // 10. GET SONG WITH ID (deep link)
  // ------------------------------------------------------------------
  Future<List> getSongWithId(String songId) async {
    // Usa stream_service.dart para obter a URL de áudio, se necessário
    // Mas aqui apenas buscamos os metadados
    try {
      final result = await _api.player(songId);
      final videoDetails = result['videoDetails'];
      if (videoDetails != null) {
        final track = {
          'videoId': songId,
          'title': videoDetails['title'] ?? '',
          'artists': [{ 'name': videoDetails['author'] ?? '' }],
          'thumbnails': videoDetails['thumbnail']?['thumbnails'] ?? [],
          'duration': int.tryParse(videoDetails['lengthSeconds'] ?? '0') ?? 0,
        };
        return [true, [track]];
      }
    } catch (_) {}
    return [false, null];
  }

  // ------------------------------------------------------------------
  // 11. GET LYRICS
  // ------------------------------------------------------------------
  dynamic getLyrics(String browseId) {
    printINFO("⚠️ getLyrics não implementado ainda");
    return '';
  }

  // ------------------------------------------------------------------
  // 12. GET CONTENT RELATED TO SONG
  // ------------------------------------------------------------------
  dynamic getContentRelatedToSong(String videoId, String hlCode) {
    printINFO("⚠️ getContentRelatedToSong não implementado ainda");
    return [];
  }

  // ------------------------------------------------------------------
  // 13. GET SEARCH SUGGESTIONS
  // ------------------------------------------------------------------
  Future<List<String>> getSearchSuggestion(String queryStr) async {
    // Pode ser implementado com /music/get_search_suggestions
    printINFO("⚠️ getSearchSuggestion não implementado ainda");
    return [];
  }

  @override
  void onClose() {
    _api.onClose();
    super.onClose();
  }
}
