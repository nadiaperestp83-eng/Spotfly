// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart' as getx;
import 'package:http/http.dart' as http;

import '../models/media_Item_builder.dart';
import '../utils/helper.dart';
import 'constant.dart';

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

/// MusicServices agora é apenas um CLIENTE HTTP para o roteador de
/// metadados no Railway (que por sua vez fala com o YouTube Music via
/// `ytmusicapi`). Nenhum áudio passa por aqui — este serviço só lida
/// com JSON (busca, home, playlists, álbuns, artistas, letras).
///
/// Toda chamada é protegida por try/catch: se o Railway estiver fora
/// do ar ou a rede falhar, os métodos devolvem uma estrutura vazia
/// (nunca lançam exceção para a UI, exceto onde isso já era esperado).
class MusicServices extends getx.GetxService {
  static const Duration _timeout = Duration(seconds: 12);

  @override
  void onInit() {
    super.onInit();
    printINFO("🎵 MusicServices inicializado (proxy: $proxyBaseUrl)");
  }

  set hlCode(String code) {
    printINFO("hlCode set to: $code (idioma é definido no servidor Railway)");
  }

  // ============================================================
  //  NÚCLEO HTTP
  // ============================================================

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final cleanQuery = <String, String>{};
    query?.forEach((key, value) {
      if (value != null) cleanQuery[key] = value.toString();
    });
    return Uri.parse('$proxyBaseUrl$path').replace(
      queryParameters: cleanQuery.isEmpty ? null : cleanQuery,
    );
  }

  /// GET genérico contra o Railway. Retorna `null` em qualquer falha
  /// (rede, timeout, status != 200, JSON inválido) para que cada método
  /// público decida seu próprio fallback "inteligente" sem derrubar o app.
  Future<dynamic> _get(String path, [Map<String, dynamic>? query]) async {
    final uri = _uri(path, query);
    try {
      printINFO("📡 GET $uri");
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        printERROR("❌ $path retornou ${response.statusCode}");
        return null;
      }
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on TimeoutException {
      printERROR("⏱️ Timeout em $path");
      return null;
    } catch (e) {
      printERROR("❌ Erro de rede em $path: $e");
      return null;
    }
  }

  // ============================================================
  //  MÉTODOS PÚBLICOS
  // ============================================================

  // ------------------------------------------------------------------
  // 1. SEARCH - categoriza resultados
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> search(
    String query, {
    String? filter,
    String? scope,
    int limit = 30,
    bool ignoreSpelling = false,
    String? filterParams,
  }) async {
    final data = await _get('/search', {
      'q': query,
      'limit': limit,
      'filter': filter,
      'ignore_spelling': ignoreSpelling,
    });

    if (data == null) return {};

    try {
      final List results = (data['results'] as List?) ?? [];
      final Map<String, List<Map<String, dynamic>>> categorized = {
        'Songs': [],
        'Videos': [],
        'Albums': [],
        'Artists': [],
        'Featured playlists': [],
        'Community playlists': [],
      };

      for (final raw in results) {
        final item = Map<String, dynamic>.from(raw as Map);
        final category = _categoryFor(item);
        if (category == null) continue;
        categorized[category]!.add(_normalizeResultItem(item, category));
      }

      categorized.removeWhere((key, value) => value.isEmpty);
      printINFO("📊 Categorias encontradas: ${categorized.keys}");
      return categorized;
    } catch (e) {
      printERROR("❌ Erro ao processar resposta de search: $e");
      return {};
    }
  }

  String? _categoryFor(Map<String, dynamic> item) {
    final resultType = (item['resultType'] as String?)?.toLowerCase() ?? '';
    final category = (item['category'] as String?)?.toLowerCase() ?? '';
    final combined = '$resultType $category';

    if (combined.contains('song')) return 'Songs';
    if (combined.contains('video')) return 'Videos';
    if (combined.contains('album')) return 'Albums';
    if (combined.contains('artist')) return 'Artists';
    if (combined.contains('community')) return 'Community playlists';
    if (combined.contains('playlist')) return 'Featured playlists';
    // fallback por campos presentes
    if (item['videoId'] != null) return 'Songs';
    if (item['browseId'] != null) {
      final id = item['browseId'] as String;
      if (id.startsWith('MPRE')) return 'Albums';
      if (id.startsWith('UC')) return 'Artists';
    }
    if (item['playlistId'] != null) return 'Featured playlists';
    return null;
  }

  Map<String, dynamic> _normalizeResultItem(
      Map<String, dynamic> item, String category) {
    item['thumbnails'] = _safeThumbnails(item['thumbnails']);
    if (category == 'Songs' || category == 'Videos') {
      item['duration'] = _durationSeconds(item);
      item['album'] = _normalizedAlbum(item['album']);
    } else if (category == 'Artists') {
      // Artist.fromJson espera a chave 'artist' (nome), não 'name'
      item['artist'] ??= item['artist'] ?? item['title'];
    }
    return item;
  }

  // ------------------------------------------------------------------
  // 2. GET HOME
  // ------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getHome({int limit = 4}) async {
    final data = await _get('/get_home', {'limit': limit});
    if (data == null) return [];

    try {
      final List sections = (data['sections'] as List?) ?? [];
      final result = <Map<String, dynamic>>[];
      for (final raw in sections) {
        final section = Map<String, dynamic>.from(raw as Map);
        final contents = (section['contents'] as List?) ?? [];
        final items = contents
            .map((e) {
              final item = Map<String, dynamic>.from(e as Map);
              item['thumbnails'] = _safeThumbnails(item['thumbnails']);
              return item;
            })
            .where((item) => item.isNotEmpty)
            .toList();
        if (items.isNotEmpty) {
          result.add({'title': section['title'] ?? '', 'contents': items});
        }
      }
      printINFO("📊 Home retornou ${result.length} seções");
      return result;
    } catch (e) {
      printERROR("❌ Erro ao processar Home: $e");
      return [];
    }
  }

  // ------------------------------------------------------------------
  // 3. GET CHARTS - fallback usando search (sem endpoint dedicado)
  // ------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getCharts(String category,
      {String? countryCode}) async {
    printINFO("⚠️ getCharts: usando search como fallback.");
    final categorized = await search(category, limit: 30);
    if (categorized.isEmpty) return [];
    final allItems = categorized.values.expand((v) => v).toList();
    if (allItems.isEmpty) return [];
    return [
      {'title': category, 'contents': allItems}
    ];
  }

  // ------------------------------------------------------------------
  // 4. GET WATCH PLAYLIST - tracks vêm como List<MediaItem>
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
    final empty = {
      'tracks': <MediaItem>[],
      'playlistId': playlistId ?? '',
      'lyrics': null,
      'related': null,
      'additionalParamsForNext': null,
    };

    final data = await _get('/get_watch_playlist', {
      'videoId': videoId.isNotEmpty ? videoId : null,
      'playlistId': playlistId,
      'limit': limit,
      'radio': radio,
      'shuffle': shuffle,
    });

    if (data == null) return empty;

    try {
      final List rawTracks = (data['tracks'] as List?) ?? [];
      final tracks = _toMediaItems(rawTracks);
      return {
        'tracks': tracks,
        'playlistId': data['playlistId'] ?? playlistId ?? '',
        'lyrics': data['lyrics'],
        'related': data['related'],
        // O ytmusicapi já devolve a lista completa (sem paginação por
        // token nesta rota), então não há continuação adicional.
        'additionalParamsForNext': null,
      };
    } catch (e) {
      printERROR("❌ Erro ao processar getWatchPlaylist: $e");
      return empty;
    }
  }

  // ------------------------------------------------------------------
  // 5. GET PLAYLIST OR ALBUM SONGS
  //    Retorna, no nível raiz, as chaves que Playlist.fromJson /
  //    Album.fromJson esperam, MAIS 'tracks' como List<MediaItem>.
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
        final data =
            await _get('/get_playlist', {'playlistId': playlistId, 'limit': limit});
        if (data == null) return {};
        final map = Map<String, dynamic>.from(data as Map);
        final rawTracks = (map['tracks'] as List?) ?? [];
        return {
          ...map,
          'playlistId': map['id'] ?? playlistId,
          'itemCount': map['trackCount']?.toString() ?? rawTracks.length.toString(),
          'thumbnails': _safeThumbnails(map['thumbnails']),
          'description': map['description'] ?? 'Playlist',
          'tracks': _toMediaItems(rawTracks),
        };
      } else if (albumId != null) {
        final data = await _get('/get_album', {'browseId': albumId});
        if (data == null) return {};
        final map = Map<String, dynamic>.from(data as Map);
        final rawTracks = (map['tracks'] as List?) ?? [];
        return {
          ...map,
          'browseId': albumId,
          'thumbnails': _safeThumbnails(map['thumbnails']),
          'description': map['description'] ?? map['type'] ?? 'Album',
          'tracks': _toMediaItems(rawTracks),
          'other_versions': map['other_versions'] ?? [],
        };
      }
      return {};
    } catch (e) {
      printERROR("❌ Erro no getPlaylistOrAlbumSongs: $e");
      return {};
    }
  }

  // ------------------------------------------------------------------
  // 6. GET ARTIST
  //    Monta as chaves ("Top songs", "Videos", "Albums", "Singles & EPs")
  //    que ArtistScreenController já espera, sem chave 'params' (assim
  //    a UI usa o caminho direto, sem precisar de continuação).
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getArtist(String artistId) async {
    final fallback = {
      'name': 'Artist $artistId',
      'artist': 'Artist $artistId',
      'browseId': artistId,
      'thumbnails': _safeThumbnails(null),
      'description': '',
      'subscribers': '0',
      'radioId': '',
      'Top songs': {'content': []},
      'Videos': {'content': []},
      'Albums': {'content': []},
      'Singles & EPs': {'content': []},
    };

    final data = await _get('/get_artist', {'browseId': artistId});
    if (data == null) return fallback;

    try {
      final map = Map<String, dynamic>.from(data as Map);
      List<Map<String, dynamic>> section(String key) {
        final sec = map[key];
        if (sec is! Map) return [];
        final results = sec['results'];
        if (results is! List) return [];
        return results
            .map((e) {
              final item = Map<String, dynamic>.from(e as Map);
              item['thumbnails'] = _safeThumbnails(item['thumbnails']);
              if (key == 'songs') {
                item['duration'] = _durationSeconds(item);
                item['album'] = _normalizedAlbum(item['album']);
              }
              return item;
            })
            .toList();
      }

      return {
        'name': map['name'] ?? 'Artist $artistId',
        'artist': map['name'] ?? 'Artist $artistId',
        'browseId': map['channelId'] ?? artistId,
        'thumbnails': _safeThumbnails(map['thumbnails']),
        'description': map['description'] ?? '',
        'subscribers': map['subscribers']?.toString() ?? '0',
        'radioId': map['radioId'] ?? '',
        'Top songs': {'content': section('songs')},
        'Videos': {'content': section('videos')},
        'Albums': {'content': section('albums')},
        'Singles & EPs': {'content': section('singles')},
      };
    } catch (e) {
      printERROR("❌ Erro ao processar getArtist: $e");
      return fallback;
    }
  }

  // ------------------------------------------------------------------
  // 7. GET ARTIST RELATED CONTENT
  //    Não há paginação por token no proxy (o ytmusicapi já devolve as
  //    listas completas em getArtist), então isso só existe para não
  //    quebrar chamadas legadas — na prática, getArtist já entrega tudo
  //    sem a chave 'params', então este método não deveria ser acionado.
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getArtistRelatedContent(
    dynamic browseEndpointOrArtistId,
    String tabName, {
    int limit = 10,
    Map<String, dynamic>? additionalParams,
  }) async {
    printINFO("⚠️ getArtistRelatedContent: sem continuação suportada pelo proxy.");
    return {'results': [], 'additionalParams': '&ctoken=null&continuation=null'};
  }

  // Método com typo para compatibilidade com chamadas existentes na UI
  Future<Map<String, dynamic>> getArtistRealtedContent(
    dynamic browseEndpointOrArtistId,
    String tabName, {
    int limit = 10,
    Map<String, dynamic>? additionalParams,
  }) {
    return getArtistRelatedContent(browseEndpointOrArtistId, tabName,
        limit: limit, additionalParams: additionalParams);
  }

  // ------------------------------------------------------------------
  // 8. GET SEARCH CONTINUATION - não suportado pelo proxy atual
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getSearchContinuation(
    Map<String, dynamic> continuationParams, {
    int limit = 10,
  }) async {
    printINFO("⚠️ getSearchContinuation não suportado.");
    return {};
  }

  // ------------------------------------------------------------------
  // 9. GET SONG YEAR - via search
  // ------------------------------------------------------------------
  Future<String> getSongYear(String songId) async {
    try {
      final categorized = await search(songId, limit: 10);
      final allItems = categorized.values.expand((v) => v).toList();
      final match = allItems.firstWhere(
        (item) => item['videoId'] == songId,
        orElse: () => allItems.isNotEmpty ? allItems.first : {},
      );
      if (match['year'] != null) return match['year'].toString();
    } catch (_) {}
    return DateTime.now().year.toString();
  }

  // ------------------------------------------------------------------
  // 10. GET SONG WITH ID - devolve [bool, List<MediaItem>]
  // ------------------------------------------------------------------
  Future<List> getSongWithId(String songId) async {
    try {
      final categorized = await search(songId, limit: 10);
      final allItems = categorized.values.expand((v) => v).toList();
      final match = allItems.firstWhere(
        (item) => item['videoId'] == songId,
        orElse: () => {},
      );
      if (match.isNotEmpty && match['videoId'] != null) {
        return [true, _toMediaItems([match])];
      }
    } catch (e) {
      printERROR("❌ Erro no getSongWithId: $e");
    }
    return [false, null];
  }

  // ------------------------------------------------------------------
  // 11. GET LYRICS
  // ------------------------------------------------------------------
  Future<String> getLyrics(String browseId) async {
    final data = await _get('/get_lyrics', {'browseId': browseId});
    if (data == null) return '';
    try {
      return (data['lyrics'] as String?) ?? '';
    } catch (e) {
      printERROR("❌ Erro ao obter letras: $e");
      return '';
    }
  }

  // ------------------------------------------------------------------
  // 12. GET CONTENT RELATED TO SONG (rádio a partir da música atual)
  // ------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getContentRelatedToSong(
      String videoId, String hlCode) async {
    final data = await _get('/get_watch_playlist', {
      'videoId': videoId,
      'radio': true,
      'limit': 20,
    });
    if (data == null) return [];
    try {
      final List rawTracks = (data['tracks'] as List?) ?? [];
      return rawTracks
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((t) => t['videoId'] != videoId)
          .map((t) {
            t['thumbnails'] = _safeThumbnails(t['thumbnails']);
            t['duration'] = _durationSeconds(t);
            return t;
          })
          .toList();
    } catch (e) {
      printERROR("❌ Erro no getContentRelatedToSong: $e");
      return [];
    }
  }

  // ------------------------------------------------------------------
  // 13. GET SEARCH SUGGESTIONS
  // ------------------------------------------------------------------
  Future<List<String>> getSearchSuggestion(String queryStr) async {
    final data = await _get('/get_search_suggestions', {'q': queryStr});
    if (data == null) return [];
    try {
      return List<String>.from(data['suggestions'] ?? []);
    } catch (e) {
      printERROR("❌ Erro em getSearchSuggestion: $e");
      return [];
    }
  }

  // ============================================================
  //  HELPERS DE NORMALIZAÇÃO / CONVERSÃO
  // ============================================================

  List<Map<String, dynamic>> _safeThumbnails(dynamic thumbnails) {
    if (thumbnails is List && thumbnails.isNotEmpty) {
      return thumbnails
          .map((t) => Map<String, dynamic>.from(t as Map))
          .toList();
    }
    return [
      {'url': ''}
    ];
  }

  int _durationSeconds(Map<String, dynamic> item) {
    if (item['duration_seconds'] != null) {
      return int.tryParse(item['duration_seconds'].toString()) ?? 0;
    }
    if (item['duration'] is int) return item['duration'] as int;
    final durationStr = item['duration']?.toString();
    if (durationStr == null || durationStr.isEmpty) return 0;
    final parts = durationStr.split(':').map((p) => int.tryParse(p) ?? 0).toList();
    if (parts.length == 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
    if (parts.length == 2) return parts[0] * 60 + parts[1];
    if (parts.length == 1) return parts[0];
    return 0;
  }

  /// Garante que 'album' tenha a chave 'id' quando existir, pois
  /// MediaItemBuilder só considera o álbum válido se `album['id'] != null`.
  Map<String, dynamic>? _normalizedAlbum(dynamic album) {
    if (album == null) return null;
    if (album is Map) {
      final map = Map<String, dynamic>.from(album);
      map['id'] ??= map['browseId'] ?? map['playlistId'];
      map['name'] ??= map['title'];
      return map;
    }
    return null;
  }

  /// Converte uma lista de tracks (Map cru vindo do proxy) para
  /// List<MediaItem>, que é o que player_controller.dart e os
  /// controllers de Playlist/Album esperam em `content['tracks']`.
  List<MediaItem> _toMediaItems(List rawTracks) {
    final result = <MediaItem>[];
    for (final raw in rawTracks) {
      try {
        final track = Map<String, dynamic>.from(raw as Map);
        if (track['videoId'] == null) continue;
        track['thumbnails'] = _safeThumbnails(track['thumbnails']);
        track['duration'] = _durationSeconds(track);
        track['album'] = _normalizedAlbum(track['album']);
        result.add(MediaItemBuilder.fromJson(track));
      } catch (e) {
        printERROR("❌ Erro ao converter track em MediaItem: $e");
        continue;
      }
    }
    return result;
  }
}
