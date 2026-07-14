// ignore_for_file: constant_identifier_names

import 'package:audio_service/audio_service.dart';
import 'package:dart_ytmusic_api/yt_music.dart';
import 'package:get/get.dart' as getx;
import 'package:hive/hive.dart';

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
  //  CLIENTE DO DART_YTMUSIC_API (versão 1.3.7)
  // ============================================================
  final YTMusic _ytApi = YTMusic();
  Future<void>? _initFuture;

  /// Garante que _ytApi.initialize() rodou antes de qualquer chamada.
  /// Chamadas subsequentes reutilizam o mesmo Future (não reinicializa).
  Future<void> _ensureInitialized() {
    _initFuture ??= _ytApi.initialize(hl: 'pt-BR');
    return _initFuture!;
  }

  /// Executa um getter que pode não existir na versão atual do pacote
  /// dart_ytmusic_api sem derrubar o bloco try/catch inteiro que o chama.
  T? _safe<T>(T? Function() getter) {
    try {
      return getter();
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  //  INICIALIZAÇÃO
  // ============================================================
  @override
  void onInit() {
    super.onInit();
    printINFO("🎵 MusicServices inicializado com dart_ytmusic_api 1.3.7");
    _ensureInitialized();
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
      await _ensureInitialized();
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
        final map = _searchResultToMap(item);
        if (map.isEmpty) continue;

        final category = _inferCategory(item);
        if (categorized.containsKey(category)) {
          categorized[category]!.add(map);
        } else {
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
  // 2. GET HOME - usa getHomeSections() (versão 1.3.7)
  // ------------------------------------------------------------------
  Future<dynamic> getHome({int limit = 4}) async {
    try {
      printINFO("🏠 Buscando Home via dart_ytmusic_api (getHomeSections)...");
      await _ensureInitialized();
      final sections = await _ytApi.getHomeSections();

      final List<Map<String, dynamic>> result = [];
      for (var section in sections) {
        try {
          final items = _sectionItemsToMaps(section.contents);
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
      await _ensureInitialized();
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
      await _ensureInitialized();
      if (videoId.isNotEmpty) {
        printINFO("🎵 Obtendo música: $videoId");
        // Usa getUpNexts para obter a música? Não, melhor usar getSong (se existir) ou getPlaylistVideos
        // Como não há getSong, usamos search ou getPlaylistVideos? 
        // Vamos usar search com o videoId como fallback, mas o ideal seria ter getSong.
        // Na versão 1.3.7, não há getSong diretamente, então usamos search com o videoId.
        final dynamic results = await _ytApi.search(videoId);
        final song = results.firstWhere(
          (item) => item.videoId == videoId,
          orElse: () => results.isNotEmpty ? results.first : null,
        );
        if (song != null) {
          final track = _searchResultToTrack(song);
          return {
            'tracks': [track],
            'playlistId': playlistId ?? '',
            'lyrics': null,
            'related': null,
            'additionalParamsForNext': null,
          };
        }
        // Se não encontrar, busca sugestões
        final upNexts = await _ytApi.getUpNexts(videoId);
        if (upNexts.isNotEmpty) {
          final tracks = upNexts.map((item) => _searchResultToTrack(item)).toList();
          return {
            'tracks': tracks,
            'playlistId': playlistId ?? '',
            'lyrics': null,
            'related': null,
            'additionalParamsForNext': null,
          };
        }
      } else if (playlistId != null) {
        printINFO("📋 Obtendo playlist: $playlistId");
        final dynamic playlist = await _ytApi.getPlaylist(playlistId);
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
      await _ensureInitialized();
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
  // 6. GET ARTIST - com suporte a músicas, álbuns, singles
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getArtist(String artistId) async {
    try {
      printINFO("🎤 Obtendo artista: $artistId");
      await _ensureInitialized();
      final dynamic artist = await _ytApi.getArtist(artistId);
      // Também buscamos músicas, álbuns e singles para enriquecer
      final songs = await _ytApi.getArtistSongs(artistId);
      final albums = await _ytApi.getArtistAlbums(artistId);
      final singles = await _ytApi.getArtistSingles(artistId);

      return {
        'id': _safe(() => artist.artistId) ?? artistId,
        'name': _safe(() => artist.name) ?? '',
        'thumbnails': _safe<dynamic>(() => artist.thumbnails)?.map((t) => {'url': t.url}).toList() ?? [],
        'description': _safe(() => artist.description) ?? '',
        'subscribers': _safe(() => artist.subscribers)?.toString() ?? '0',
        'radioId': '',
        'songs': songs.map((s) => _songToMap(s)).toList(),
        'albums': albums.map((a) => _albumToMap(a)).toList(),
        'singles': singles.map((s) => _songToMap(s)).toList(),
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
        'songs': [],
        'albums': [],
        'singles': [],
      };
    }
  }

  // ------------------------------------------------------------------
  // 7. GET ARTIST RELATED CONTENT - fallback para getArtistSongs/Albums/Singles
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getArtistRelatedContent(
    String artistId,
    String tabName, {
    int limit = 10,
    Map<String, dynamic>? additionalParams,
  }) async {
    printINFO("⚠️ getArtistRelatedContent: usando getArtistSongs/Albums/Singles.");
    try {
      await _ensureInitialized();
      List<dynamic> items = [];
      final lowerTab = tabName.toLowerCase();
      if (lowerTab.contains('song')) {
        items = await _ytApi.getArtistSongs(artistId);
      } else if (lowerTab.contains('album')) {
        items = await _ytApi.getArtistAlbums(artistId);
      } else if (lowerTab.contains('single')) {
        items = await _ytApi.getArtistSingles(artistId);
      } else {
        // fallback: search
        final results = await _ytApi.search('$artistId $tabName');
        items = results;
      }
      return {
        'contents': items.map((e) => _songToMap(e)).toList(),
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
  // 9. GET SONG YEAR - via getUpNexts ou search
  // ------------------------------------------------------------------
  Future<String> getSongYear(String songId) async {
    try {
      await _ensureInitialized();
      final dynamic results = await _ytApi.search(songId);
      final song = results.firstWhere(
        (item) => item.videoId == songId,
        orElse: () => results.isNotEmpty ? results.first : null,
      );
      if (song != null && song.year != null) {
        return song.year.toString();
      }
    } catch (_) {}
    return DateTime.now().year.toString();
  }

  // ------------------------------------------------------------------
  // 10. GET SONG WITH ID - via search
  // ------------------------------------------------------------------
  Future<List> getSongWithId(String songId) async {
    try {
      await _ensureInitialized();
      final dynamic results = await _ytApi.search(songId);
      final song = results.firstWhere(
        (item) => item.videoId == songId,
        orElse: () => results.isNotEmpty ? results.first : null,
      );
      if (song != null) {
        final track = _searchResultToTrack(song);
        return [true, [track]];
      }
    } catch (_) {}
    return [false, null];
  }

  // ------------------------------------------------------------------
  // 11. GET LYRICS - usa getLyrics(videoId) (versão 1.3.7)
  // ------------------------------------------------------------------
  dynamic getLyrics(String browseId) {
    // Como getLyrics retorna Future<String?>, precisamos de async
    return _getLyricsAsync(browseId);
  }

  Future<dynamic> _getLyricsAsync(String videoId) async {
    try {
      printINFO("📝 Obtendo letras para: $videoId");
      await _ensureInitialized();
      final dynamic lyrics = await _ytApi.getLyrics(videoId);
      return lyrics ?? '';
    } catch (e) {
      printERROR("Erro ao obter letras: $e");
      return '';
    }
  }

  // ------------------------------------------------------------------
  // 12. GET CONTENT RELATED TO SONG - usa getUpNexts
  // ------------------------------------------------------------------
  dynamic getContentRelatedToSong(String videoId, String hlCode) {
    return _getContentRelatedToSongAsync(videoId);
  }

  Future<dynamic> _getContentRelatedToSongAsync(String videoId) async {
    try {
      await _ensureInitialized();
      final upNexts = await _ytApi.getUpNexts(videoId);
      return upNexts.map((item) => _searchResultToMap(item)).toList();
    } catch (e) {
      printERROR("Erro no getContentRelatedToSong: $e");
      return [];
    }
  }

  // ------------------------------------------------------------------
  // 13. GET SEARCH SUGGESTIONS - não suportado
  // ------------------------------------------------------------------
  Future<List<String>> getSearchSuggestion(String queryStr) async {
    printINFO("⚠️ getSearchSuggestion não suportado.");
    return [];
  }

  // ============================================================
  //  FUNÇÕES AUXILIARES DE CONVERSÃO
  // ============================================================

  /// Converte SearchResult para Map
  Map<String, dynamic> _searchResultToMap(dynamic result) {
    final map = <String, dynamic>{};
    try {
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
    } catch (e) {
      printERROR("Erro ao converter SearchResult: $e");
    }
    return map;
  }

  /// Converte SearchResult para track (usado em getWatchPlaylist)
  Map<String, dynamic> _searchResultToTrack(dynamic result) {
    return {
      'videoId': result.videoId ?? '',
      'title': result.title ?? '',
      'artists': result.artists?.map((a) => {'name': a.name}).toList() ?? [],
      'album': result.album != null ? {'title': result.album.title} : {},
      'thumbnails': result.thumbnails?.map((t) => {'url': t.url}).toList() ?? [],
      'duration': result.duration?.inSeconds ?? 0,
      'year': result.year?.toString() ?? '',
      'playlistId': result.playlistId ?? '',
    };
  }

  /// Converte Song (do pacote) para Map
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

  /// Converte itens da Home (cada item pode ser um SectionItem)
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

  /// Inferir categoria com base nos campos disponíveis
  String _inferCategory(dynamic result) {
    if (result.videoId != null) {
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
        final title = result.title?.toLowerCase() ?? '';
        if (title.contains('community')) return 'Community playlists';
        return 'Featured playlists';
      }
    } else if (result.playlistId != null) {
      final title = result.title?.toLowerCase() ?? '';
      if (title.contains('community')) return 'Community playlists';
      return 'Featured playlists';
    }
    return 'Songs';
  }

  /// Converte Song (do pacote) para track (usado em getWatchPlaylist)
  Map<String, dynamic> _songToTrack(dynamic song) {
    return {
      'videoId': song.videoId ?? '',
      'title': song.title ?? '',
      'artists': song.artists?.map((a) => {'name': a.name}).toList() ?? [],
      'album': song.album != null ? {'title': song.album.title} : {},
      'thumbnails': song.thumbnails?.map((t) => {'url': t.url}).toList() ?? [],
      'duration': song.duration?.inSeconds ?? 0,
      'year': song.year?.toString() ?? '',
      'playlistId': '',
    };
  }

  int _sumTotalDuration(List<dynamic> songs) {
    int total = 0;
    for (var song in songs) {
      final int dur = (song.duration?.inSeconds as int?) ?? 0;
      total += dur;
    }
    return total;
  }
}
