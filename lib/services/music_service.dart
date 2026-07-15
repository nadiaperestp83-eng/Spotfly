// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart' as getx;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yte;

import '../models/media_Item_builder.dart';
import '../utils/helper.dart';
import 'proxy_config.dart';
import 'yt_client_provider.dart';

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

/// MusicServices agora segue a MESMA técnica da Musify (gokadzev/Musify):
/// tudo roda no próprio app via `youtube_explode_dart` — busca, home e
/// streaming — sem NENHUM backend próprio. Não existe mais Railway/
/// ytmusicapi na equação; o app fala direto com o YouTube.
///
/// Todas as chamadas de rede passam por `_withFallback`, que tenta
/// primeiro o cliente com proxy embutido e, se a rede falhar
/// (SocketException, TimeoutException ou 403), cai automaticamente
/// para o cliente direto — sem travar a UI e sem exigir configuração
/// manual do usuário.
///
/// IMPORTANTE (limitação honesta): `youtube_explode_dart` enxerga o
/// YouTube "normal", não o YouTube Music. Então não existem mais os
/// conceitos de Álbum oficial, Rádio/"watch playlist" personalizada ou
/// letras (lyrics) — a Musify também não tem isso (ela é essencialmente
/// um player de vídeos do YouTube focado em áudio). O que dá para manter
/// 100% fiel: busca de vídeos/músicas, canais (usados como "artista"),
/// playlists do YouTube, e streaming.
class MusicServices extends getx.GetxService {
  late final yte.YoutubeExplode _ytProxy;
  late final yte.YoutubeExplode _ytDirect;

  @override
  void onInit() {
    super.onInit();
    _ytProxy = YtClientProvider.createProxyClient();
    _ytDirect = YtClientProvider.createDefaultClient();
    printINFO(
        "🎵 MusicServices inicializado (100% on-device, youtube_explode_dart, com fallback de proxy)");
  }

  @override
  void onClose() {
    _ytProxy.close();
    _ytDirect.close();
    super.onClose();
  }

  set hlCode(String code) {
    printINFO("hlCode set to: $code (ignorado, youtube_explode_dart não segmenta por idioma)");
  }

  // ============================================================
  //  FALLBACK DE REDE (proxy -> direto)
  // ============================================================

  /// Executa [action] usando o cliente com proxy embutido. Se falhar por
  /// motivo de rede (SocketException, TimeoutException ou HTTP 403),
  /// tenta de novo imediatamente com o cliente direto (sem proxy). Erros
  /// que não são de rede (parsing, vídeo indisponível, etc.) são
  /// propagados na hora, sem tentar de novo.
  Future<T> _withFallback<T>(
    Future<T> Function(yte.YoutubeExplode yt) action,
  ) async {
    try {
      return await action(_ytProxy).timeout(ProxyConfig.proxyTimeout);
    } catch (e) {
      if (!_isNetworkFailure(e)) {
        rethrow;
      }
      printINFO("⚠️ Proxy falhou ($e) — tentando conexão direta...");
    }

    // Fallback: conexão direta. Se falhar aqui, o erro sobe para quem
    // chamou _withFallback, que decide como logar/tratar.
    return await action(_ytDirect).timeout(ProxyConfig.directTimeout);
  }

  bool _isNetworkFailure(Object e) {
    if (e is SocketException || e is TimeoutException) return true;
    final msg = e.toString().toLowerCase();
    return msg.contains("403") || msg.contains("forbidden");
  }

  // ============================================================
  //  MÉTODOS PÚBLICOS
  // ============================================================

  // ------------------------------------------------------------------
  // 1. SEARCH
  //    youtube_explode_dart não categoriza como o YT Music (não separa
  //    Álbuns de Músicas, por exemplo). Fazemos o melhor esforço:
  //    'Songs' vem de search.search (vídeos), 'Artists' e
  //    'Featured playlists' vêm de search.searchContent quando o canal/
  //    playlist aparece nos resultados.
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> search(
    String query, {
    String? filter,
    String? scope,
    int limit = 30,
    bool ignoreSpelling = false,
    String? filterParams,
  }) async {
    final Map<String, List<Map<String, dynamic>>> categorized = {
      'Songs': [],
      'Artists': [],
      'Featured playlists': [],
    };

    try {
      printINFO("🔍 Buscando (on-device): '$query'");
      final videos = await _withFallback((yt) => yt.search.search(query));
      categorized['Songs'] = videos.take(limit).map(_mapFromVideo).toList();
    } catch (e) {
      printERROR("❌ Erro na busca de vídeos: $e");
    }

    // Melhor esforço: canais e playlists via searchContent. Se a API não
    // bater 1:1 (nomes de campos podem variar entre versões do pacote),
    // isso falha silenciosamente e a busca continua funcionando só com
    // 'Songs', que é o essencial para tocar música.
    try {
      final content =
          await _withFallback((yt) => yt.search.searchContent(query));
      for (final item in content) {
        try {
          final dynamic dynItem = item;
          if (dynItem is yte.Video) {
            continue; // já coberto por search.search acima
          } else if (_looksLikeChannel(dynItem)) {
            categorized['Artists']!.add(_mapFromChannelLike(dynItem));
          } else if (_looksLikePlaylist(dynItem)) {
            categorized['Featured playlists']!.add(_mapFromPlaylistLike(dynItem));
          }
        } catch (_) {
          continue;
        }
      }
    } catch (e) {
      printERROR("⚠️ searchContent indisponível/mudou de forma nesta versão: $e");
    }

    categorized.removeWhere((key, value) => value.isEmpty);
    printINFO("📊 Categorias encontradas: ${categorized.keys}");
    return categorized;
  }

  bool _looksLikeChannel(dynamic item) {
    final typeName = item.runtimeType.toString().toLowerCase();
    return typeName.contains('channel');
  }

  bool _looksLikePlaylist(dynamic item) {
    final typeName = item.runtimeType.toString().toLowerCase();
    return typeName.contains('playlist');
  }

  Map<String, dynamic> _mapFromChannelLike(dynamic c) {
    return {
      'browseId': _safe(() => c.id.value.toString()) ?? '',
      'artist': _safe(() => c.title as String) ?? '',
      'name': _safe(() => c.title as String) ?? '',
      'thumbnails': _thumbFromDynamic(c),
      'resultType': 'artist',
    };
  }

  Map<String, dynamic> _mapFromPlaylistLike(dynamic p) {
    return {
      'playlistId': _safe(() => p.id.value.toString()) ?? '',
      'browseId': _safe(() => p.id.value.toString()) ?? '',
      'title': _safe(() => p.title as String) ?? '',
      'thumbnails': _thumbFromDynamic(p),
      'resultType': 'playlist',
    };
  }

  List<Map<String, dynamic>> _thumbFromDynamic(dynamic item) {
    final url = _safe(() => item.thumbnails.highResUrl as String) ??
        _safe(() => item.thumbnails.standardResUrl as String) ??
        _safe(() => item.thumbnails.mediumResUrl as String);
    return _safeThumbnails(url == null ? null : [
      {'url': url}
    ]);
  }

  T? _safe<T>(T? Function() getter) {
    try {
      return getter();
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------
  // 2. GET HOME
  //    youtube_explode_dart não tem um feed de "página inicial"
  //    personalizado (isso é exclusivo do YT Music). Como a Musify,
  //    montamos seções a partir de buscas por termos populares.
  // ------------------------------------------------------------------
  static const List<String> _homeSeedQueries = [
    'top hits 2026',
    'músicas mais tocadas',
    'lançamentos desta semana',
  ];

  Future<List<Map<String, dynamic>>> getHome({int limit = 4}) async {
    final result = <Map<String, dynamic>>[];
    for (final query in _homeSeedQueries.take(limit)) {
      try {
        final videos = await _withFallback((yt) => yt.search.search(query));
        final items = videos.take(15).map(_mapFromVideo).toList();
        if (items.isNotEmpty) {
          result.add({'title': _titleCase(query), 'contents': items});
        }
      } catch (e) {
        printERROR("❌ Erro ao montar seção Home '$query': $e");
      }
    }
    printINFO("📊 Home retornou ${result.length} seções");
    return result;
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // ------------------------------------------------------------------
  // 3. GET CHARTS - reusa getHome/search como fallback (sem endpoint
  //    de charts oficial fora do YT Music)
  // ------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getCharts(String category,
      {String? countryCode}) async {
    try {
      final videos = await _withFallback((yt) => yt.search.search(category));
      final items = videos.take(30).map(_mapFromVideo).toList();
      if (items.isEmpty) return [];
      return [
        {'title': category, 'contents': items}
      ];
    } catch (e) {
      printERROR("❌ Erro no getCharts: $e");
      return [];
    }
  }

  // ------------------------------------------------------------------
  // 4. GET WATCH PLAYLIST
  //    Sem "rádio" oficial do YT Music: usamos vídeos relacionados do
  //    YouTube (getRelatedVideos) como substituto de "próximas músicas".
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

    try {
      if (videoId.isNotEmpty) {
        final video = await _withFallback((yt) => yt.videos.get(videoId));
        final tracks = <Map<String, dynamic>>[_mapFromVideo(video)];

        try {
          final related =
              await _withFallback((yt) => yt.videos.getRelatedVideos(video));
          if (related != null) {
            tracks.addAll(related.take(limit - 1).map(_mapFromVideo));
          }
        } catch (e) {
          printERROR("⚠️ Vídeos relacionados indisponíveis: $e");
        }

        return {
          'tracks': _toMediaItems(tracks),
          'playlistId': playlistId ?? '',
          'lyrics': null, // sem API de letras fora do YT Music
          'related': null,
          'additionalParamsForNext': null,
        };
      } else if (playlistId != null) {
        final videos = await _withFallback(
            (yt) => yt.playlists.getVideos(playlistId).take(limit).toList());
        return {
          'tracks': _toMediaItems(videos.map(_mapFromVideo).toList()),
          'playlistId': playlistId,
          'lyrics': null,
          'related': null,
          'additionalParamsForNext': null,
        };
      }
      return empty;
    } catch (e) {
      printERROR("❌ Erro no getWatchPlaylist: $e");
      return empty;
    }
  }

  // ------------------------------------------------------------------
  // 5. GET PLAYLIST OR ALBUM SONGS
  //    Não existe "álbum oficial" fora do YT Music: albumId é tratado
  //    como um playlistId comum (é o que a Musify também faz).
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getPlaylistOrAlbumSongs({
    String? playlistId,
    String? albumId,
    int limit = 3000,
    bool related = false,
    int suggestionsLimit = 0,
  }) async {
    final id = playlistId ?? albumId;
    if (id == null) return {};

    try {
      final playlist = await _withFallback((yt) => yt.playlists.get(id));
      final videos = await _withFallback(
          (yt) => yt.playlists.getVideos(id).take(limit).toList());

      final thumbUrl = _safe(() => playlist.thumbnails.highResUrl) ??
          _safe(() => playlist.thumbnails.standardResUrl);

      return {
        'title': playlist.title,
        'playlistId': playlist.id.value,
        'browseId': playlist.id.value,
        'thumbnails': _safeThumbnails(thumbUrl == null ? null : [
          {'url': thumbUrl}
        ]),
        'description': playlist.description.isNotEmpty
            ? playlist.description
            : 'Playlist',
        'itemCount': (playlist.videoCount ?? videos.length).toString(),
        'artists': [
          {'name': playlist.author}
        ],
        'year': '',
        'tracks': _toMediaItems(videos.map(_mapFromVideo).toList()),
        'other_versions': [],
      };
    } catch (e) {
      printERROR("❌ Erro no getPlaylistOrAlbumSongs: $e");
      return {};
    }
  }

  // ------------------------------------------------------------------
  // 6. GET ARTIST
  //    "Artista" = canal do YouTube. 'Top songs' vem dos uploads do
  //    canal. Sem chave 'params', então a UI usa o caminho direto
  //    (sem paginação por token).
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

    try {
      final channel = await _withFallback((yt) => yt.channels.get(artistId));
      List<yte.Video> uploads = [];
      try {
        final uploadsList = await _withFallback(
            (yt) => yt.channels.getUploadsFromPage(artistId));
        uploads = uploadsList.take(30).toList();
      } catch (e) {
        printERROR("⚠️ Uploads do canal indisponíveis: $e");
      }

      return {
        'name': channel.title,
        'artist': channel.title,
        'browseId': channel.id.value,
        'thumbnails': _safeThumbnails(
            [{'url': channel.logoUrl}]),
        'description': '',
        'subscribers': _safe(() => channel.subscribersCount.toString()) ?? '',
        'radioId': '',
        'Top songs': {'content': uploads.map(_mapFromVideo).toList()},
        'Videos': {'content': []},
        'Albums': {'content': []},
        'Singles & EPs': {'content': []},
      };
    } catch (e) {
      printERROR("❌ Erro no getArtist: $e");
      return fallback;
    }
  }

  // ------------------------------------------------------------------
  // 7. GET ARTIST RELATED CONTENT - sem paginação por token disponível
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getArtistRelatedContent(
    dynamic browseEndpointOrArtistId,
    String tabName, {
    int limit = 10,
    Map<String, dynamic>? additionalParams,
  }) async {
    return {'results': [], 'additionalParams': '&ctoken=null&continuation=null'};
  }

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
  // 8. GET SEARCH CONTINUATION - não suportado
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> getSearchContinuation(
    Map<String, dynamic> continuationParams, {
    int limit = 10,
  }) async {
    return {};
  }

  // ------------------------------------------------------------------
  // 9. GET SONG YEAR
  // ------------------------------------------------------------------
  Future<String> getSongYear(String songId) async {
    try {
      final video = await _withFallback((yt) => yt.videos.get(songId));
      if (video.uploadDate != null) return video.uploadDate!.year.toString();
    } catch (_) {}
    return DateTime.now().year.toString();
  }

  // ------------------------------------------------------------------
  // 10. GET SONG WITH ID
  // ------------------------------------------------------------------
  Future<List> getSongWithId(String songId) async {
    try {
      final video = await _withFallback((yt) => yt.videos.get(songId));
      return [true, _toMediaItems([_mapFromVideo(video)])];
    } catch (e) {
      printERROR("❌ Erro no getSongWithId: $e");
      return [false, null];
    }
  }

  // ------------------------------------------------------------------
  // 11. GET LYRICS - sem fonte de letras fora do YT Music (limitação
  //     conhecida, igual à Musify sem um provedor de letras dedicado)
  // ------------------------------------------------------------------
  Future<String> getLyrics(String browseId) async {
    return '';
  }

  // ------------------------------------------------------------------
  // 12. GET CONTENT RELATED TO SONG
  // ------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getContentRelatedToSong(
      String videoId, String hlCode) async {
    try {
      final video = await _withFallback((yt) => yt.videos.get(videoId));
      final related =
          await _withFallback((yt) => yt.videos.getRelatedVideos(video));
      if (related == null) return [];
      return related.map(_mapFromVideo).toList();
    } catch (e) {
      printERROR("❌ Erro no getContentRelatedToSong: $e");
      return [];
    }
  }

  // ------------------------------------------------------------------
  // 13. GET SEARCH SUGGESTIONS
  // ------------------------------------------------------------------
  Future<List<String>> getSearchSuggestion(String queryStr) async {
    try {
      final suggestions =
          await _withFallback((yt) => yt.search.getQuerySuggestions(queryStr));
      return List<String>.from(suggestions);
    } catch (e) {
      printERROR("⚠️ getSearchSuggestion indisponível nesta versão: $e");
      return [];
    }
  }

  // ============================================================
  //  HELPERS DE CONVERSÃO
  // ============================================================

  Map<String, dynamic> _mapFromVideo(yte.Video v) {
    String? thumbUrl;
    try {
      thumbUrl = v.thumbnails.highResUrl;
    } catch (_) {
      thumbUrl = null;
    }
    return {
      'videoId': v.id.value,
      'title': v.title,
      'artists': [
        {'name': v.author, 'id': v.channelId.value}
      ],
      'album': null, // YouTube "normal" não tem conceito de álbum
      'thumbnails': _safeThumbnails(thumbUrl == null ? null : [
        {'url': thumbUrl}
      ]),
      'duration': v.duration?.inSeconds ?? 0,
      'year': v.uploadDate?.year.toString() ?? '',
      'playlistId': '',
      'resultType': 'song',
    };
  }

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

  /// Converte uma lista de tracks (Map cru) para List<MediaItem>, que é
  /// o que player_controller.dart e os controllers de Playlist/Album
  /// esperam em `content['tracks']`.
  List<MediaItem> _toMediaItems(List<Map<String, dynamic>> rawTracks) {
    final result = <MediaItem>[];
    for (final track in rawTracks) {
      try {
        if (track['videoId'] == null || (track['videoId'] as String).isEmpty) {
          continue;
        }
        result.add(MediaItemBuilder.fromJson(track));
      } catch (e) {
        printERROR("❌ Erro ao converter track em MediaItem: $e");
        continue;
      }
    }
    return result;
  }
}
