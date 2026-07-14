// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart' as getx;
import 'package:hive/hive.dart';

import '/models/album.dart';
import '/services/utils.dart';
import '../utils/helper.dart';
import 'constant.dart';
import 'continuations.dart';
import 'nav_parser.dart';

// ============================================================
//  DEFINIÇÃO DA EXCEÇÃO NetworkError (se não existir em outro lugar)
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
  final Map<String, String> _headers = {
    'user-agent': userAgent,
    'accept': '*/*',
    'accept-encoding': 'gzip, deflate',
    'content-type': 'application/json',
    'content-encoding': 'gzip',
    'origin': domain,
    'cookie': 'CONSENT=YES+1',
  };

  final Map<String, dynamic> _context = {
    'context': {
      'client': {
        "clientName": "WEB_REMIX",
        "clientVersion": "1.20230213.01.00",
      },
      'user': {}
    }
  };

  @override
  void onInit() {
    init();
    super.onInit();
  }

  final dio = Dio();

  Future<void> init() async {
    final date = DateTime.now();
    _context['context']['client']['clientVersion'] =
        "1.${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}.01.00";
    final signatureTimestamp = getDatestamp() - 1;
    _context['playbackContext'] = {
      'contentPlaybackContext': {'signatureTimestamp': signatureTimestamp},
    };

    final appPrefsBox = Hive.box('AppPrefs');
    hlCode = appPrefsBox.get('contentLanguage') ?? "en";
    if (appPrefsBox.containsKey('visitorId')) {
      final visitorData = appPrefsBox.get("visitorId");
      if (visitorData != null && !isExpired(epoch: visitorData['exp'])) {
        _headers['X-Goog-Visitor-Id'] = visitorData['id'];
        appPrefsBox.put("visitorId", {
          'id': visitorData['id'],
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 2590200
        });
        printINFO("Got Visitor id (${visitorData['id']}) from Box");
        return;
      }
    }

    final visitorId = await genrateVisitorId();
    if (visitorId != null) {
      _headers['X-Goog-Visitor-Id'] = visitorId;
      printINFO("New Visitor id generated ($visitorId)");
      appPrefsBox.put("visitorId", {
        'id': visitorId,
        'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 2592000
      });
      return;
    }
    _headers['X-Goog-Visitor-Id'] =
        visitorId ?? "CgttN24wcmd5UzNSWSi2lvq2BjIKCgJKUBIEGgAgYQ%3D%3D";
  }

  set hlCode(String code) {
    _context['context']['client']['hl'] = code;
  }

  Future<String?> genrateVisitorId() async {
    try {
      final response =
          await dio.get(domain, options: Options(headers: _headers));
      final reg = RegExp(r'ytcfg\.set\s*\(\s*({.+?})\s*\)\s*;');
      final matches = reg.firstMatch(response.data.toString());
      String? visitorId;
      if (matches != null) {
        final ytcfg = json.decode(matches.group(1).toString());
        visitorId = ytcfg['VISITOR_DATA']?.toString();
      }
      return visitorId;
    } catch (e) {
      return null;
    }
  }

  Future<Response> _sendRequest(String action, Map<dynamic, dynamic> data,
      {additionalParams = "", int retryCount = 0}) async {
    const maxRetries = 3;
    try {
      final response = await dio
          .post("$baseUrl$action$fixedParms$additionalParams",
              options: Options(
                headers: _headers,
              ),
              data: data)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return response;
      }

      if (retryCount >= maxRetries) {
        printINFO("Max retries atingido para $action (status ${response.statusCode})");
        throw NetworkError();
      }

      await Future.delayed(Duration(milliseconds: 500 * (retryCount + 1)));
      return _sendRequest(action, data,
          additionalParams: additionalParams, retryCount: retryCount + 1);
    } on DioException catch (e) {
      printINFO("Error $e");
      throw NetworkError();
    }
  }

  Future<dynamic> getHome({int limit = 4}) async {
    final data = Map.from(_context);
    data["browseId"] = "FEmusic_home";
    final response = await _sendRequest("browse", data);
    final results = nav(response.data, single_column_tab + section_list);
    final home = [...parseMixedContent(results)];

    final sectionList =
        nav(response.data, single_column_tab + ['sectionListRenderer']);
    if (sectionList.containsKey('continuations')) {
      requestFunc(additionalParams) async {
        return (await _sendRequest("browse", data,
                additionalParams: additionalParams))
            .data;
      }

      parseFunc(contents) => parseMixedContent(contents);
      final x = (await getContinuations(sectionList, 'sectionListContinuation',
          limit - home.length, requestFunc, parseFunc));
      home.addAll([...x]);
    }

    return home;
  }

  Future<List<Map<String, dynamic>>> getCharts(String catogory,
      {String? countryCode}) async {
    final List<Map<String, dynamic>> charts = [];
    final data = Map.from(_context);

    data['browseId'] = 'FEmusic_charts';
    data['context']['client']["hl"] = 'en';
    if (countryCode != null) {
      data['formData'] = {
        'selectedValues': [countryCode]
      };
    }
    final response = (await _sendRequest('browse', data)).data;
    final results = nav(response, single_column_tab + section_list);
    results.removeAt(0);
    for (dynamic result in results) {
      if (nav(result, [
            "musicCarouselShelfRenderer",
            "header",
            "musicCarouselShelfBasicHeaderRenderer",
            ...title_text
          ]) ==
          "Video charts") {
        for (dynamic item in result['musicCarouselShelfRenderer']['contents']) {
          final chartItem =
              await getChartItems(parseChartsItemBrowseId(item), catogory);
          charts.add(chartItem);
        }
      } else {
        continue;
      }
    }

    return charts;
  }

  Future<Map<String, dynamic>> getChartItems(
      Map<String, dynamic> item, String catogory) async {
    final catString = catogory == "TMV" ? "Top Music Videos" : "Trending";
    if ((item['title'])!.contains(catString)) {
      final songs = (await getPlaylistOrAlbumSongs(
          playlistId: item['browseId']))['tracks'];
      final limitedSongs = songs.length > 24 ? songs.sublist(0, 24) : songs;
      return {'title': item['title'], 'contents': limitedSongs};
    }
    return {'title': item['title'], 'contents': []};
  }

  Future<Map<String, dynamic>> getWatchPlaylist(
      {String videoId = "",
      String? playlistId,
      int limit = 25,
      bool radio = false,
      bool shuffle = false,
      String? additionalParamsNext,
      bool onlyRelated = false}) async {
    if (videoId.isNotEmpty && videoId.substring(0, 4) == "MPED") {
      videoId = videoId.substring(4);
    }
    final data = Map.from(_context);
    data['enablePersistentPlaylistPanel'] = true;
    data['isAudioOnly'] = true;
    data['tunerSettingValue'] = 'AUTOMIX_SETTING_NORMAL';
    if (videoId == "" && playlistId == null) {
      throw Exception(
          "You must provide either a video id, a playlist id, or both");
    }
    if (videoId != "") {
      data['videoId'] = videoId;
      playlistId ??= "RDAMVM$videoId";

      if (!(radio || shuffle)) {
        data['watchEndpointMusicSupportedConfigs'] = {
          'watchEndpointMusicConfig': {
            'hasPersistentPlaylistPanel': true,
            'musicVideoType': "MUSIC_VIDEO_TYPE_ATV",
          }
        };
      }
    }

    playlistId = validatePlaylistId(playlistId!);
    data['playlistId'] = playlistId;
    final isPlaylist =
        playlistId.startsWith('PL') || playlistId.startsWith('OLA');
    if (shuffle) {
      data['params'] = "wAEB8gECKAE%3D";
    }
    if (radio) {
      data['params'] = "wAEB";
    }

    final List<dynamic> tracks = [];
    dynamic lyricsBrowseId, relatedBrowseId, playlist;
    final results = {};

    if (additionalParamsNext == null) {
      final response = (await _sendRequest("next", data)).data;
      final watchNextRenderer = nav(response, [
        'contents',
        'singleColumnMusicWatchNextResultsRenderer',
        'tabbedRenderer',
        'watchNextTabbedResultsRenderer'
      ]);

      lyricsBrowseId = getTabBrowseId(watchNextRenderer, 1);
      relatedBrowseId = getTabBrowseId(watchNextRenderer, 2);
      if (onlyRelated) {
        return {
          'lyrics': lyricsBrowseId,
          'related': relatedBrowseId,
        };
      }

      results.addAll(nav(watchNextRenderer, [
        ...tab_content,
        'musicQueueRenderer',
        'content',
        'playlistPanelRenderer'
      ]));
      playlist = results['contents']
          .map((content) => nav(content,
              ['playlistPanelVideoRenderer', ...navigation_playlist_id]))
          .where((e) => e != null)
          .toList()
          .first;
      tracks.addAll(parseWatchPlaylist(results['contents']));
    }

    dynamic additionalParamsForNext;
    if (results.containsKey('continuations') || additionalParamsNext != null) {
      requestFunc(additionalParams) async =>
          (await _sendRequest("next", data, additionalParams: additionalParams))
              .data;
      parseFunc(contents) => parseWatchPlaylist(contents);
      final x = await getContinuations(results, 'playlistPanelContinuation',
          limit - tracks.length, requestFunc, parseFunc,
          ctokenPath: isPlaylist ? '' : 'Radio',
          isAdditionparamReturnReq: true,
          additionalParams_: additionalParamsNext);
      additionalParamsForNext = x[1];
      tracks.addAll(List<dynamic>.from(x[0]));
    }

    return {
      'tracks': tracks,
      'playlistId': playlist,
      'lyrics': lyricsBrowseId,
      'related': relatedBrowseId,
      'additionalParamsForNext': additionalParamsForNext
    };
  }

  Future<String> getAlbumBrowseId(String audioPlaylistId) async {
    final response = await dio.get("${domain}playlist",
        options: Options(headers: _headers),
        queryParameters: {"list": audioPlaylistId});
    final reg = RegExp(r'\"MPRE.+?\"');
    final matchs = reg.firstMatch(response.data.toString());
    if (matchs != null) {
      final x = (matchs[0])!;
      final res = (x.substring(1)).split("\\")[0];
      return res;
    }
    return audioPlaylistId;
  }

  dynamic getContentRelatedToSong(String videoId, String hlCode) async {
    final params = await getWatchPlaylist(videoId: videoId, onlyRelated: true);
    final data = Map.from(_context);
    data['browseId'] = params['related'];
    data['context']['client']['hl'] = hlCode;
    final response = (await _sendRequest('browse', data)).data;
    final sections = nav(response, ['contents'] + section_list);
    final x = parseMixedContent(sections);
    return x;
  }

  dynamic getLyrics(String browseId) async {
    final data = Map.from(_context);
    data['browseId'] = browseId;
    final response = (await _sendRequest('browse', data)).data;
    return nav(
      response,
      ['contents', ...section_list_item, ...description_shelf, ...description],
    );
  }

  Future<Map<String, dynamic>> getPlaylistOrAlbumSongs(
      {String? playlistId,
      String? albumId,
      int limit = 3000,
      bool related = false,
      int suggestionsLimit = 0}) async {
    String browseId = playlistId != null
        ? (playlistId.startsWith("VL") ? playlistId : "VL$playlistId")
        : albumId!;
    if (albumId != null && albumId.contains("OLAK5uy")) {
      browseId = await getAlbumBrowseId(browseId);
    }
    final data = Map.from(_context);
    data['browseId'] = browseId;
    final Map<String, dynamic> response =
        (await _sendRequest('browse', data)).data;
    if (playlistId != null) {
      final Map<String, dynamic> header =
          nav(response, ['header', "musicDetailHeaderRenderer"]) ??
              nav(response, [
                'contents',
                "twoColumnBrowseResultsRenderer",
                'tabs',
                0,
                "tabRenderer",
                "content",
                "sectionListRenderer",
                "contents",
                0,
                "musicResponsiveHeaderRenderer"
              ]);

      final Map<String, dynamic> results =
          nav(response, musicPlaylistShelfRenderer) ??
              nav(
                response,
                [
                  'contents',
                  "singleColumnBrowseResultsRenderer",
                  "tabs",
                  0,
                  "tabRenderer",
                  "content",
                  'sectionListRenderer',
                  'contents',
                  0,
                  "musicPlaylistShelfRenderer"
                ],
              );
      final Map<String, dynamic> playlist = {'id': results['playlistId']};

      playlist['title'] = nav(header, title_text);
      playlist['thumbnails'] = nav(header, thumnail_cropped) ??
          nav(header, [
            "thumbnail",
            "musicThumbnailRenderer",
            "thumbnail",
            "thumbnails"
          ]);
      playlist["description"] = nav(header, description);
      final int runCount = header['subtitle']['runs'].length;
      if (runCount > 1) {
        playlist['author'] = {
          'name': nav(header, subtitle2),
          'id': nav(header, ['subtitle', 'runs', 2] + navigation_browse_id)
        };
        if (runCount == 5) {
          playlist['year'] = nav(header, subtitle3);
        }
      }

      final int secondSubtitleRunCount =
          header['secondSubtitle']['runs'].length;
      final String count = (((header['secondSubtitle']['runs']
                      [secondSubtitleRunCount % 3]['text'])
                  .split(' ')[0])
              .split(',') as List)
          .join();
      final int songCount = int.parse(count);
      if (header['secondSubtitle']['runs'].length > 1) {
        playlist['duration'] = header['secondSubtitle']['runs']
            [(secondSubtitleRunCount % 3) + 2]['text'];
      }
      playlist['trackCount'] = songCount;

      requestFuncCountinuation(cont) async =>
          (await _sendRequest("browse", {...data, ...cont})).data;

      if (songCount > 0) {
        playlist['tracks'] = parsePlaylistItems(results['contents']);
        limit = songCount;

        List<dynamic> parseFunc(contents) => parsePlaylistItems(contents);

        playlist['tracks'] = [
          ...(playlist['tracks']),
          ...(await getContinuationsPlaylist(
              results, limit, requestFuncCountinuation, parseFunc))
        ];
      }
      playlist['duration_seconds'] = sumTotalDuration(playlist);
      return playlist;
    }

    //album content
    final album = parseAlbumHeader(response);
    dynamic results = nav(
          response,
          [
            'contents',
            "twoColumnBrowseResultsRenderer",
            "secondaryContents",
            'sectionListRenderer',
            'contents',
            0,
            'musicShelfRenderer'
          ],
        ) ??
        nav(
          response,
          [
            'contents',
            "singleColumnBrowseResultsRenderer",
            "tabs",
            0,
            "tabRenderer",
            "content",
            'sectionListRenderer',
            'contents',
            0,
            'musicShelfRenderer'
          ],
        );

    album['tracks'] = parsePlaylistItems(results['contents'],
        artistsM: album['artists'],
        thumbnailsM: album["thumbnails"],
        albumIdName: {"id": albumId, 'name': album['title']},
        albumYear: album['year'],
        isAlbum: true);
    results = nav(
      response,
      [...single_column_tab, ...section_list, 1, 'musicCarouselShelfRenderer'],
    );
    if (results != null) {
      List contents = [];
      if (results.runtimeType.toString().contains("Iterable") ||
          results.runtimeType.toString().contains("List")) {
        for (dynamic result in results) {
          contents.add(parseAlbum(result['musicTwoRowItemRenderer']));
        }
      } else {
        contents
            .add(parseAlbum(results['contents'][0]['musicTwoRowItemRenderer']));
      }
      album['other_versions'] = contents;
    }
    album['duration_seconds'] = sumTotalDuration(album);

    return album;
  }

  Future<List<String>> getSearchSuggestion(String queryStr) async {
    final data = Map.from(_context);
    data['input'] = queryStr;
    final res = nav(
            (await _sendRequest("music/get_search_suggestions", data)).data,
            ['contents', 0, 'searchSuggestionsSectionRenderer', 'contents']) ??
        [];
    return res
        .map<String?>((item) {
          return (nav(item, [
            'searchSuggestionRenderer',
            'navigationEndpoint',
            'searchEndpoint',
            'query'
          ])).toString();
        })
        .whereType<String>()
        .toList();
  }

  ///Specially created for deep-links
  Future<List> getSongWithId(String songId) async {
    final data = Map.of(_context);
    data['videoId'] = songId;
    final response = (await _sendRequest("player", data)).data;
    final category =
        nav(response, ["microformat", "microformatDataRenderer", "category"]);
    if (category == "Music" ||
        (response["videoDetails"]).containsKey("musicVideoType")) {
      final list = await getWatchPlaylist(videoId: songId);
      return [true, list['tracks']];
    }
    return [false, null];
  }

  // ============================================================
  //  MÉTODOS QUE ESTAVAM FALTANDO (restaurados e corrigidos)
  // ============================================================

  /// Obtém o ano de uma música
  Future<String> getSongYear(String songId) async {
    try {
      final data = Map.of(_context);
      data['videoId'] = songId;
      final response = await _sendRequest("player", data);
      final year = nav(response.data, [
        'microformat',
        'microformatDataRenderer',
        'publishedDate'
      ]);
      if (year != null && year is String) {
        final match = RegExp(r'\d{4}').firstMatch(year);
        return match?.group(0) ?? DateTime.now().year.toString();
      }
    } catch (_) {}
    return DateTime.now().year.toString();
  }

  /// Obtém informações de um artista
  Future<Map<String, dynamic>> getArtist(String artistId) async {
    final data = Map.of(_context);
    data['browseId'] = artistId;
    try {
      final response = await _sendRequest("browse", data);
      final header = nav(response.data, [
        'header',
        'musicImmersiveHeaderRenderer'
      ]) ??
          nav(response.data, [
            'header',
            'musicArtistHeaderRenderer'
          ]);
      if (header != null) {
        return {
          'id': artistId,
          'name': nav(header, title_text) ?? 'Unknown Artist',
          'thumbnails': nav(header, thumnail_cropped) ?? [],
          'description': nav(header, description) ?? '',
        };
      }
    } catch (_) {}
    return {
      'id': artistId,
      'name': 'Artist $artistId',
      'thumbnails': [],
      'description': '',
    };
  }

  /// Obtém conteúdo relacionado a um artista (com suporte a parâmetros adicionais)
  Future<Map<String, dynamic>> getArtistRealtedContent(
      String artistId, String tabName,
      {int limit = 10, Map<String, dynamic>? additionalParams}) async {
    try {
      final data = Map.of(_context);
      data['browseId'] = artistId;
      data['params'] = _getArtistTabParams(tabName);
      // Se houver parâmetros adicionais (para continuação), mescla
      if (additionalParams != null && additionalParams.isNotEmpty) {
        data.addAll(additionalParams);
      }
      final response = await _sendRequest("browse", data);
      
      // Tenta extrair os conteúdos da aba
      final results = nav(response.data, [
        'contents',
        'twoColumnBrowseResultsRenderer',
        'secondaryContents',
        'sectionListRenderer',
        'contents',
        0,
        'musicShelfRenderer',
        'contents'
      ]);
      
      // Tenta obter parâmetros de continuação, se houver
      final continuation = nav(response.data, [
        'contents',
        'twoColumnBrowseResultsRenderer',
        'secondaryContents',
        'sectionListRenderer',
        'continuations',
        0,
        'nextContinuationData'
      ]);
      
      return {
        'contents': results is List ? results : [],
        'additionalParams': continuation != null ? {'continuation': continuation} : {},
      };
    } catch (e) {
      printERROR("Error fetching artist content: $e");
      return {
        'contents': [],
        'additionalParams': {},
      };
    }
  }

  String _getArtistTabParams(String tabName) {
    // Mapeamento básico para as abas do artista
    switch (tabName.toLowerCase()) {
      case 'songs':
        return 'EgWKAQIIAWoKEAoQCRADEAA%3D';
      case 'albums':
        return 'EgWKAQIIAWoKEAoQCRADEAA%3D';
      case 'playlists':
        return 'EgWKAQIIAWoKEAoQCRADEAA%3D';
      default:
        return '';
    }
  }

  /// Obtém continuação da busca (scroll infinito) - usado pelo SearchCoordinator
  Future<Map<String, dynamic>> getSearchContinuation(
      Map<String, dynamic> continuationParams,
      {int limit = 10}) async {
    try {
      final data = Map.of(_context);
      data.addAll(continuationParams);
      final response = await _sendRequest("search", data);
      return response.data;
    } catch (_) {
      return {};
    }
  }

  // ============================================================
  //  🚀 MÉTODO SEARCH REFATORADO
  // ============================================================
  Future<Map<String, dynamic>> search(String query,
      {String? filter,
      String? scope,
      int limit = 30,
      bool ignoreSpelling = false,
      String? filterParams}) async {
    final data = Map.of(_context);
    data['context']['client']["hl"] = 'en';
    data['query'] = query;

    final Map<String, dynamic> searchResults = {};
    final filters = [
      'albums',
      'artists',
      'playlists',
      'community_playlists',
      'featured_playlists',
      'songs',
      'videos'
    ];

    if (filter != null && !filters.contains(filter)) {
      throw Exception(
          'Invalid filter provided. Please use one of the following filters or leave out the parameter: ${filters.join(', ')}');
    }

    final scopes = ['library', 'uploads'];

    if (scope != null && !scopes.contains(scope)) {
      throw Exception(
          'Invalid scope provided. Please use one of the following scopes or leave out the parameter: ${scopes.join(', ')}');
    }

    if (scope == scopes[1] && filter != null) {
      throw Exception(
          'No filter can be set when searching uploads. Please unset the filter parameter when scope is set to uploads.');
    }

    final params = getSearchParams(filter, scope, ignoreSpelling);

    if (filterParams != null || params != null) {
      data['params'] = filterParams ?? params;
    }

    final response = (await _sendRequest("search", data)).data;

    if (response['contents'] == null) {
      return searchResults;
    }

    dynamic results;

    if ((response['contents']).containsKey('tabbedSearchResultsRenderer')) {
      final tabIndex =
          scope == null || filter != null ? 0 : scopes.indexOf(scope) + 1;
      results = response['contents']['tabbedSearchResultsRenderer']['tabs']
          [tabIndex]['tabRenderer']['content'];
    } else {
      results = response['contents'];
    }

    // ==========================================================
    // 🔥 OBTÉM OS ITENS CRUOS (mixedItems) usando parseMixedContent
    // ==========================================================
    final mixedItems = parseMixedContent(results);
    printINFO("🔍 Itens brutos recebidos: ${mixedItems.length}");

    // ==========================================================
    // 🔥 CATEGORIZA POR TIPO (e NÃO por artista)
    // ==========================================================
    final categorized = _categorizeItems(mixedItems);

    // ==========================================================
    // 🔥 FALLBACK: extrai músicas das playlists se necessário
    // ==========================================================
    if (!categorized.containsKey('Songs') || (categorized['Songs'] as List).isEmpty) {
      printINFO("⚠️ Nenhuma música encontrada. Tentando extrair das playlists...");
      final songsFromPlaylists = _extractSongsFromPlaylists(categorized);
      if (songsFromPlaylists.isNotEmpty) {
        categorized['Songs'] = songsFromPlaylists;
        printINFO("🎵 Extraídas ${songsFromPlaylists.length} músicas das playlists.");
      }
    }

    // ==========================================================
    // 🔥 NORMALIZA AS CHAVES (capitalização)
    // ==========================================================
    final normalized = _normalizeKeys(categorized);

    // ==========================================================
    // 🔥 RETORNA O RESULTADO
    // ==========================================================
    searchResults.addAll(normalized);
    printINFO("📋 Categorias finais: ${normalized.keys}");
    return searchResults;
  }

  // ============================================================
  //  FUNÇÕES AUXILIARES DE EXTRAÇÃO E CATEGORIZAÇÃO
  // ============================================================

  /// Categoriza os itens com base no tipo (resultType ou runtimeType)
  Map<String, List<dynamic>> _categorizeItems(List<dynamic> items) {
    final Map<String, List<dynamic>> categories = {
      'Songs': [],
      'Videos': [],
      'Albums': [],
      'Artists': [],
      'Playlists': [],
      'Featured playlists': [],
      'Community playlists': [],
    };

    for (var item in items) {
      String type = _getItemType(item);
      switch (type) {
        case 'song':
        case 'track':
        case 'music':
          categories['Songs']!.add(item);
          break;
        case 'video':
        case 'music_video':
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
          if (_isCommunityPlaylist(item)) {
            categories['Community playlists']!.add(item);
          } else {
            categories['Featured playlists']!.add(item);
          }
          break;
        default:
          // Fallback: tenta adivinhar pela estrutura
          if (item is Map) {
            if (item.containsKey('tracks') || item.containsKey('items')) {
              categories['Playlists']!.add(item);
            } else if (item.containsKey('artist') || item.containsKey('channel')) {
              categories['Artists']!.add(item);
            } else if (item.containsKey('album') || (item.containsKey('title') && item.containsKey('year'))) {
              categories['Albums']!.add(item);
            } else if (item.containsKey('title') && item.containsKey('artist')) {
              categories['Songs']!.add(item);
            }
          }
      }
    }

    // Remove chaves vazias
    categories.removeWhere((key, value) => value.isEmpty);
    return categories;
  }

  /// Determina o tipo do item baseado em campos comuns
  String _getItemType(dynamic item) {
    if (item is! Map) return 'unknown';

    // Prioriza campos explícitos
    if (item.containsKey('resultType')) {
      final type = item['resultType'].toString().toLowerCase();
      if (type.contains('song') || type.contains('track')) return 'song';
      if (type.contains('video')) return 'video';
      if (type.contains('album')) return 'album';
      if (type.contains('artist')) return 'artist';
      if (type.contains('playlist')) return 'playlist';
    }

    // Verifica por campos típicos
    if (item.containsKey('videoId') && item.containsKey('title')) {
      if (item.containsKey('length') && item['length'] is int && item['length'] < 600) {
        return 'song';
      }
      return 'video';
    }
    if (item.containsKey('browseId') && item.containsKey('title')) {
      if (item.containsKey('trackCount')) return 'album';
      if (item.containsKey('artist') || item.containsKey('channel')) return 'artist';
      if (item.containsKey('playlistId')) return 'playlist';
    }
    if (item.containsKey('tracks') || item.containsKey('items')) {
      return 'playlist';
    }
    return 'unknown';
  }

  /// Verifica se a playlist é comunitária
  bool _isCommunityPlaylist(dynamic item) {
    if (item is! Map) return false;
    final title = item['title']?.toString().toLowerCase() ?? '';
    final id = item['id']?.toString().toLowerCase() ?? '';
    return title.contains('community') || id.contains('community');
  }

  /// Extrai músicas de todas as playlists encontradas
  List<dynamic> _extractSongsFromPlaylists(Map<String, List<dynamic>> categories) {
    final List<dynamic> extracted = [];
    final playlistKeys = ['Playlists', 'Featured playlists', 'Community playlists'];
    for (var key in playlistKeys) {
      if (categories.containsKey(key)) {
        final playlists = categories[key]!;
        for (var playlist in playlists) {
          if (playlist is Map) {
            final tracks = playlist['tracks'] ?? playlist['items'] ?? playlist['contents'];
            if (tracks is List) {
              extracted.addAll(tracks);
            }
          }
        }
      }
    }
    return extracted;
  }

  /// Normaliza as chaves para capitalização consistente
  Map<String, List<dynamic>> _normalizeKeys(Map<String, List<dynamic>> input) {
    final Map<String, List<dynamic>> normalized = {};
    input.forEach((key, value) {
      String newKey = key;
      if (key.toLowerCase() == 'songs' || key.toLowerCase() == 'tracks') newKey = 'Songs';
      else if (key.toLowerCase() == 'videos') newKey = 'Videos';
      else if (key.toLowerCase() == 'albums') newKey = 'Albums';
      else if (key.toLowerCase() == 'artists' || key.toLowerCase() == 'channels') newKey = 'Artists';
      else if (key.toLowerCase() == 'playlists' || key.toLowerCase() == 'featured_playlists') newKey = 'Featured playlists';
      else if (key.toLowerCase() == 'community_playlists') newKey = 'Community playlists';
      else newKey = key;
      if (normalized.containsKey(newKey)) {
        normalized[newKey]!.addAll(value);
      } else {
        normalized[newKey] = List.from(value);
      }
    });
    return normalized;
  }
}
