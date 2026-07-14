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

// ============================================================
//  AudioQuality (usado nas settings)
// ============================================================
enum AudioQuality {
  Low,
  High,
}

class MusicServices extends getx.GetxService {
  // ============================================================
  //  CLIENTE DO DART_YTMUSIC_API
  // ============================================================
  final YtMusicApi _ytApi = YtMusicApi(hl: 'pt-BR'); // ou 'en'

  // ============================================================
  //  INICIALIZAÇÃO
  // ============================================================
  @override
  void onInit() {
    super.onInit();
    printINFO("🎵 MusicServices inicializado com dart_ytmusic_api");
  }

  set hlCode(String code) {
    // Não é mais necessário, mas mantido para compatibilidade
    printINFO("hlCode set to: $code (ignorado)");
  }

  // ============================================================
  //  MÉTODOS PÚBLICOS
  // ============================================================

  // ------------------------------------------------------------------
  // 1. SEARCH - retorna categorias (Songs, Videos, Albums, Artists, Playlists)
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
        final json = _searchResultToMap(item);
        if (json.isEmpty) continue;

        switch (item.resultType) {
          case ResultType.song:
            categorized['Songs']!.add(json);
            break;
          case ResultType.video:
            categorized['Videos']!.add(json);
            break;
          case ResultType.album:
            categorized['Albums']!.add(json);
            break;
          case ResultType.artist:
            categorized['Artists']!.add(json);
            break;
          case ResultType.playlist:
            final title = item.title?.toLowerCase() ?? '';
            final id = item.browseId?.toLowerCase() ?? '';
            if (title.contains('community') || id.contains('community')) {
              categorized['Community playlists']!.add(json);
            } else {
              categorized['Featured playlists']!.add(json);
            }
            break;
          default:
            // fallback: tenta adivinhar
            if (json.containsKey('videoId')) {
              categorized['Songs']!.add(json);
            } else if (json.containsKey('browseId') && json.containsKey('trackCount')) {
              categorized['Albums']!.add(json);
            } else if (json.containsKey('playlistId')) {
              categorized['Featured playlists']!.add(json);
            }
            break;
        }
      }

      // Remove categorias vazias
      categorized.removeWhere((key, value) => value.isEmpty);
      printINFO("📊 Categorias encontradas: ${categorized.keys}");
      return categorized;
    } catch (e) {
      printERROR("❌ Erro no search: $e");
      return {};
    }
  }

  // ------------------------------------------------------------------
  // 2. GET HOME - retorna seções (carrosséis)
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
  // 3. GET CHARTS - não implementado (usar search com filtro)
  // ------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getCharts(String category,
      {String? countryCode}) async {
    printINFO("⚠️ getCharts não implementado. Usando search como fallback.");
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
  // 4. GET WATCH PLAYLIST - obtém música ou playlist
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
        final track = _songToTrack(song);
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
        final tracks = playlist.songs.map((s) => _songToTrack(s)).toList();
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
  // 6. GET ARTIST - via dart_ytmusic_api
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
  // 7. GET ARTIST RELATED CONTENT - não implementado diretamente (usar search)
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
  // 8. GET SEARCH CONTINUATION - não suportado pelo pacote (stub)
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getSearchContinuation(
    Map<String, dynamic> continuationParams, {
    int limit = 10,
  }) async {
    printINFO("⚠️ getSearchContinuation não suportado.");
    return {};
  }

  // ------------------------------------------------------------------
  // 9. GET SONG YEAR - via getSong
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
  // 10. GET SONG WITH ID - via getSong
  // ------------------------------------------------------------------
  Future<List> getSongWithId(String songId) async {
    try {
      final song = await _ytApi.getSong(songId);
      final track = _songToTrack(song);
      return [true, [track]];
    } catch (_) {
      return [false, null];
    }
  }

  // ------------------------------------------------------------------
  // 11. GET LYRICS - não suportado (stub)
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
  // 13. GET SEARCH SUGGESTIONS - não suportado (stub)
  // ------------------------------------------------------------------
  Future<List<String>> getSearchSuggestion(String queryStr) async {
    printINFO("⚠️ getSearchSuggestion não suportado.");
    return [];
  }

  // ============================================================
  //  FUNÇÕES AUXILIARES DE CONVERSÃO
  // ============================================================

  /// Converte um SearchResult para Map<String, dynamic>
  Map<String, dynamic> _searchResultToMap(SearchResult result) {
    return {
      'title': result.title ?? '',
      'videoId': result.videoId,
      'browseId': result.browseId,
      'playlistId': result.playlistId,
      'thumbnails': result.thumbnails?.map((t) => {'url': t.url}).toList() ?? [],
      'artist': result.artist,
      'artists': result.artists,
      'album': result.album,
      'duration': result.duration?.inSeconds,
      'year': result.year,
      'trackCount': result.trackCount,
      'resultType': result.resultType.name,
    };
  }

  /// Converte os items de uma seção da Home para Map
  List<Map<String, dynamic>> _sectionItemsToMaps(List<SectionItem> items) {
    final List<Map<String, dynamic>> result = [];
    for (var item in items) {
      try {
        final map = <String, dynamic>{};
        map['title'] = item.title ?? '';
        map['thumbnails'] = item.thumbnails?.map((t) => {'url': t.url}).toList() ?? [];
        if (item.videoId != null) {
          map['videoId'] = item.videoId;
          map['resultType'] = 'song';
        } else if (item.browseId != null) {
          map['browseId'] = item.browseId;
          if (item.browseId!.startsWith('MPRE')) {
            map['resultType'] = 'album';
          } else if (item.browseId!.startsWith('UC')) {
            map['resultType'] = 'artist';
          } else if (item.browseId!.startsWith('VL')) {
            map['playlistId'] = item.browseId!.substring(2);
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

  /// Converte uma Song (do pacote) para o formato de track esperado
  Map<String, dynamic> _songToTrack(Song song) {
    return {
      'videoId': song.videoId ?? '',
      'title': song.title ?? '',
      'artists': song.artists?.map((a) => {'name': a.name}).toList() ?? [],
      'album': song.album != null ? {'title': song.album!.title} : {},
      'thumbnails': song.thumbnails?.map((t) => {'url': t.url}).toList() ?? [],
      'duration': song.duration?.inSeconds ?? 0,
      'year': song.year?.toString() ?? '',
      'playlistId': '',
    };
  }

  /// Converte Playlist para o formato esperado
  Map<String, dynamic> _playlistToMap(Playlist playlist) {
    return {
      'id': playlist.id ?? '',
      'title': playlist.title ?? '',
      'thumbnails': playlist.thumbnails?.map((t) => {'url': t.url}).toList() ?? [],
      'description': playlist.description ?? '',
      'trackCount': playlist.trackCount ?? 0,
      'duration': playlist.duration?.toString() ?? '',
      'tracks': playlist.songs.map((s) => _songToTrack(s)).toList(),
      'author': playlist.author != null ? {'name': playlist.author!.name} : {},
      'year': playlist.year?.toString() ?? '',
      'duration_seconds': _sumTotalDuration(playlist.songs),
    };
  }

  /// Converte Album para o formato esperado
  Map<String, dynamic> _albumToMap(Album album) {
    return {
      'id': album.id ?? '',
      'title': album.title ?? '',
      'thumbnails': album.thumbnails?.map((t) => {'url': t.url}).toList() ?? [],
      'description': album.description ?? '',
      'trackCount': album.trackCount ?? 0,
      'tracks': album.songs.map((s) => _songToTrack(s)).toList(),
      'artists': album.artists?.map((a) => {'name': a.name}).toList() ?? [],
      'year': album.year?.toString() ?? '',
      'duration_seconds': _sumTotalDuration(album.songs),
      'other_versions': [],
    };
  }

  int _sumTotalDuration(List<Song> songs) {
    int total = 0;
    for (var song in songs) {
      total += song.duration?.inSeconds ?? 0;
    }
    return total;
  }
}
