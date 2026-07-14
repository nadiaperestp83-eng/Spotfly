// ignore_for_file: constant_identifier_names

import 'package:audio_service/audio_service.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:get/get.dart' as getx;
import 'package:hive/hive.dart';

import '../utils/helper.dart';

// ============================================================
//  DEFINIÇÃO DA EXCEÇÃO NetworkError (mantida para compatibilidade)
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
  //  CLIENTE DO DART_YTMUSIC_API
  // ============================================================
  final YtMusicApi _ytApi = YtMusicApi(hl: 'pt-BR');

  // ============================================================
  //  INICIALIZAÇÃO
  // ============================================================
  @override
  void onInit() {
    super.onInit();
    printINFO("🎵 MusicServices inicializado com dart_ytmusic_api");
  }

  set hlCode(String code) {
    printINFO("hlCode set to: $code (ignorado)");
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
    try {
      printINFO("🔍 Buscando via dart_ytmusic_api: '$query'");
      final results = await _ytApi.search(query);

      final Map<String, List<Map<String, dynamic>>> categorized = {
        'Songs': [],
        'Videos': [],
        'Albums': [],
        'Artists': [],
        'Featured playlists': [],
        'Community playlists': [],
      };

      for (var item in results) {
        // Converte para Map de forma segura
        final map = _searchResultToMap(item);
        if (map.isEmpty) continue;

        // Determina a categoria com base no tipo (se disponível) ou inferência
        String category = _inferCategory(item);
        if (categorized.containsKey(category)) {
          categorized[category]!.add(map);
        } else {
          // fallback: Songs
          categorized['Songs']!.add(map);
        }
      }

      categorized.removeWhere((key, value) => value.isEmpty);
      printINFO("📊 Categorias encontradas: ${categorized.keys}");
      return categorized;
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
      printINFO("🏠 Buscando Home via dart_ytmusic_api...");
      final sections = await _ytApi.getHome();

      final List<Map<String, dynamic>> result = [];
      for (var section in sections) {
        try {
          final items = _sectionItemsToMaps(section.items);
          if (items.isNotEmpty) {
            result.add({
              'title': section.title ?? '',
              'contents': items,
            });
          }
        } catch (e) {
          printERROR("Erro ao parsear seção: $e");
        }
      }

      printINFO("📊 Home retornou ${result.length} seções");
      return result;
    } catch (e) {
      printERROR("❌ Erro no getHome: $e");
      return [];
    }
  }

  // ------------------------------------------------------------------
  // 3. GET CHARTS - fallback usando search
  // ------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getCharts(String category,
      {String? countryCode}) async {
    printINFO("⚠️ getCharts: usando search como fallback.");
    try {
      final results = await _ytApi.search(category);
      if (results.isEmpty) return [];
      final chartSection = {
        'title': category,
        'contents': results.map((e) => _searchResultToMap(e)).toList(),
      };
      return [chartSection];
    } catch (e) {
      printERROR("Erro no getCharts: $e");
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
      if (videoId.isNotEmpty) {
        printINFO("🎵 Obtendo música: $videoId");
        final song = await _ytApi.getSong(videoId);
        final track = _songToMap(song);
        return {
          'tracks': [track],
          'playlistId': playlistId ?? '',
          'lyrics': null,
          'related': null,
          'additionalParamsForNext': null,
        };
      } else if (playlistId != null) {
        printINFO("📋 Obtendo playlist: $playlistId");
        final playlist = await _ytApi.getPlaylist(playlistId);
        final tracks = playlist.songs.map((s) => _songToMap(s)).toList();
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
        printINFO("📋 Obtendo playlist: $playlistId");
        final playlist = await _ytApi.getPlaylist(playlistId);
        return _playlistToMap(playlist);
      } else if (albumId != null) {
        printINFO("📀 Obtendo álbum: $albumId");
        final album = await _ytApi.getAlbum(albumId);
        return _albumToMap(album);
      }
      return {};
    } catch (e) {
      printERROR("Erro no getPlaylistOrAlbumSongs: $e");
      return {};
    }
  }

  // ------------------------------------------------------------------
  // 6. GET ARTIST
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getArtist(String artistId) async {
    try {
      printINFO("🎤 Obtendo artista: $artistId");
      final artist = await _ytApi.getArtist(artistId);
      return {
        'id': artist.id ?? artistId,
        'name': artist.name ?? '',
        'thumbnails': artist.thumbnails?.map((t) => {'url': t.url}).toList() ?? [],
        'description': artist.description ?? '',
        'subscribers': artist.subscribers?.toString() ?? '0',
        'radioId': '',
      };
    } catch (e) {
      printERROR("Erro no getArtist: $e");
      return {
        'id': artistId,
        'name': 'Artist $artistId',
        'thumbnails': [],
        'description': '',
        'subscribers': '0',
        'radioId': '',
      };
    }
  }

  // ------------------------------------------------------------------
  // 7. GET ARTIST RELATED CONTENT (fallback via search)
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getArtistRelatedContent(
    String artistId,
    String tabName, {
    int limit = 10,
    Map<String, dynamic>? additionalParams,
  }) async {
    printINFO("⚠️ getArtistRelatedContent: usando search como fallback.");
    try {
      final results = await _ytApi.search('$artistId $tabName');
      return {
        'contents': results.map((e) => _searchResultToMap(e)).toList(),
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
  // 9. GET SONG YEAR
  // ------------------------------------------------------------------
  Future<String> getSongYear(String songId) async {
    try {
      final song = await _ytApi.getSong(songId);
      return song.year?.toString() ?? DateTime.now().year.toString();
    } catch (_) {
      return DateTime.now().year.toString();
    }
  }

  // ------------------------------------------------------------------
  // 10. GET SONG WITH ID
  // ------------------------------------------------------------------
  Future<List> getSongWithId(String songId) async {
    try {
      final song = await _ytApi.getSong(songId);
      final track = _songToMap(song);
      return [true, [track]];
    } catch (_) {
      return [false, null];
    }
  }

  // ------------------------------------------------------------------
  // 11-13. STUBS
  // ------------------------------------------------------------------
  dynamic getLyrics(String browseId) {
    printINFO("⚠️ getLyrics não suportado.");
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

  // ============================================================
  //  FUNÇÕES AUXILIARES DE CONVERSÃO (ajustadas para a API real)
  // ============================================================

  /// Converte SearchResult para Map, ignorando campos que não existem
  Map<String, dynamic> _searchResultToMap(dynamic result) {
    final map = <String, dynamic>{};
    try {
      // Propriedades comuns (usando getters ou campos)
      map['title'] = result.title ?? '';
      if (result.videoId != null) map['videoId'] = result.videoId;
      if (result.browseId != null) map['browseId'] = result.browseId;
      if (result.playlistId != null) map['playlistId'] = result.playlistId;
      if (result.thumbnails != null) {
        map['thumbnails'] = result.thumbnails.map((t) => {'url': t.url}).toList();
      }
      if (result.artist != null) map['artist'] = result.artist;
      if (result.artists != null) {
        map['artists'] = result.artists.map((a) => {'name': a.name}).toList();
      }
      if (result.album != null) map['album'] = result.album.title;
      if (result.duration != null) {
        map['duration'] = result.duration.inSeconds;
      }
      if (result.year != null) map['year'] = result.year;
      // trackCount e resultType não existem, então não usamos
    } catch (e) {
      printERROR("Erro ao converter SearchResult: $e");
    }
    return map;
  }

  /// Inferir categoria com base nos campos disponíveis
  String _inferCategory(dynamic result) {
    if (result.videoId != null) {
      // Se tem videoId, é música ou vídeo. Verificar se tem duração curta (música)
      if (result.duration != null && result.duration.inSeconds < 600) {
        return 'Songs';
      } else {
        return 'Videos';
      }
    } else if (result.browseId != null) {
      final id = result.browseId as String;
      if (id.startsWith('MPRE')) return 'Albums';
      if (id.startsWith('UC')) return 'Artists';
      if (id.startsWith('VL')) {
        // Playlist
        final title = result.title?.toLowerCase() ?? '';
        if (title.contains('community')) return 'Community playlists';
        return 'Featured playlists';
      }
    } else if (result.playlistId != null) {
      final title = result.title?.toLowerCase() ?? '';
      if (title.contains('community')) return 'Community playlists';
      return 'Featured playlists';
    }
    // fallback
    return 'Songs';
  }

  /// Converte itens da Home (cada item pode ser um Map ou objeto)
  List<Map<String, dynamic>> _sectionItemsToMaps(List<dynamic> items) {
    final List<Map<String, dynamic>> result = [];
    for (var item in items) {
      try {
        final map = <String, dynamic>{};
        map['title'] = item.title ?? '';
        if (item.thumbnails != null) {
          map['thumbnails'] = item.thumbnails.map((t) => {'url': t.url}).toList();
        }
        if (item.videoId != null) {
          map['videoId'] = item.videoId;
          map['resultType'] = 'song';
        } else if (item.browseId != null) {
          map['browseId'] = item.browseId;
          final id = item.browseId as String;
          if (id.startsWith('MPRE')) map['resultType'] = 'album';
          else if (id.startsWith('UC')) map['resultType'] = 'artist';
          else if (id.startsWith('VL')) {
            map['playlistId'] = id.substring(2);
            map['resultType'] = 'playlist';
          }
        }
        if (map.isNotEmpty) {
          result.add(map);
        }
      } catch (e) {
        continue;
      }
    }
    return result;
  }

  /// Converte Song (objeto) para Map
  Map<String, dynamic> _songToMap(dynamic song) {
    final map = <String, dynamic>{};
    try {
      map['videoId'] = song.videoId ?? '';
      map['title'] = song.title ?? '';
      if (song.artists != null) {
        map['artists'] = song.artists.map((a) => {'name': a.name}).toList();
      } else {
        map['artists'] = [];
      }
      if (song.album != null) {
        map['album'] = {'title': song.album.title};
      } else {
        map['album'] = {};
      }
      if (song.thumbnails != null) {
        map['thumbnails'] = song.thumbnails.map((t) => {'url': t.url}).toList();
      } else {
        map['thumbnails'] = [];
      }
      map['duration'] = song.duration?.inSeconds ?? 0;
      map['year'] = song.year?.toString() ?? '';
      map['playlistId'] = '';
    } catch (e) {
      printERROR("Erro ao converter Song: $e");
    }
    return map;
  }

  /// Converte Playlist para Map
  Map<String, dynamic> _playlistToMap(dynamic playlist) {
    final map = <String, dynamic>{};
    try {
      map['id'] = playlist.id ?? '';
      map['title'] = playlist.title ?? '';
      map['thumbnails'] = playlist.thumbnails?.map((t) => {'url': t.url}).toList() ?? [];
      map['description'] = playlist.description ?? '';
      map['trackCount'] = playlist.trackCount ?? 0;
      map['duration'] = playlist.duration?.toString() ?? '';
      map['tracks'] = playlist.songs.map((s) => _songToMap(s)).toList();
      map['author'] = playlist.author != null ? {'name': playlist.author.name} : {};
      map['year'] = playlist.year?.toString() ?? '';
      map['duration_seconds'] = _sumTotalDuration(playlist.songs);
    } catch (e) {
      printERROR("Erro ao converter Playlist: $e");
    }
    return map;
  }

  /// Converte Album para Map
  Map<String, dynamic> _albumToMap(dynamic album) {
    final map = <String, dynamic>{};
    try {
      map['id'] = album.id ?? '';
      map['title'] = album.title ?? '';
      map['thumbnails'] = album.thumbnails?.map((t) => {'url': t.url}).toList() ?? [];
      map['description'] = album.description ?? '';
      map['trackCount'] = album.trackCount ?? 0;
      map['tracks'] = album.songs.map((s) => _songToMap(s)).toList();
      map['artists'] = album.artists?.map((a) => {'name': a.name}).toList() ?? [];
      map['year'] = album.year?.toString() ?? '';
      map['duration_seconds'] = _sumTotalDuration(album.songs);
      map['other_versions'] = [];
    } catch (e) {
      printERROR("Erro ao converter Album: $e");
    }
    return map;
  }

  int _sumTotalDuration(List<dynamic> songs) {
    int total = 0;
    for (var song in songs) {
      final dur = song.duration?.inSeconds ?? 0;
      total += dur.toInt(); // converte double para int
    }
    return total;
  }
}
