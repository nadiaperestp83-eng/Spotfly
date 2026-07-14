import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/helper.dart';
import 'constant.dart';

class YouTubeMusicApi {
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
        "hl": "en",
      },
      'user': {}
    }
  };

  Future<Map<String, dynamic>> _post(String endpoint, Map<String, dynamic> data) async {
    final url = Uri.parse('$baseUrl$endpoint$fixedParms');
    try {
      printINFO("📡 POST $url");
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        printINFO("✅ $endpoint OK");
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception("Erro ${response.statusCode}: ${response.body}");
      }
    } catch (e) {
      printERROR("❌ Erro no POST $endpoint: $e");
      rethrow;
    }
  }

  // ============================================================
  //  MÉTODOS PÚBLICOS COM PARSING
  // ============================================================

  /// Retorna a Home do YouTube Music já parseada para o formato que a UI espera
  Future<List<Map<String, dynamic>>> getHome({int limit = 4}) async {
    final data = Map.from(_context);
    data['browseId'] = 'FEmusic_home';
    final response = await _post('browse', data);
    return _parseHome(response);
  }

  /// Retorna a busca já categorizada (Songs, Videos, Albums, Artists, Playlists)
  Future<Map<String, dynamic>> search(String query, {int limit = 30}) async {
    final data = Map.from(_context);
    data['query'] = query;
    // Parâmetro para buscar tudo (sem filtro específico)
    final response = await _post('search', data);
    return _parseSearch(response);
  }

  // ============================================================
  //  PARSERS
  // ============================================================

  /// Extrai as seções da Home a partir da resposta /browse
  List<Map<String, dynamic>> _parseHome(Map<String, dynamic> response) {
    final List<Map<String, dynamic>> sections = [];
    try {
      // Navega até os contents da home
      final contents = response['contents']
          ?['singleColumnBrowseResultsRenderer']
          ?['tabs']?[0]
          ?['tabRenderer']
          ?['content']
          ?['sectionListRenderer']
          ?['contents'] as List?;

      if (contents == null) return sections;

      for (var item in contents) {
        final shelf = item['musicCarouselShelfRenderer'];
        if (shelf != null) {
          final title = _getText(shelf['header']?['musicCarouselShelfBasicHeaderRenderer']?['title']);
          final items = _parseCarouselItems(shelf['contents'] as List? ?? []);
          if (title.isNotEmpty && items.isNotEmpty) {
            sections.add({
              'title': title,
              'contents': items,
            });
          }
        }
      }
    } catch (e) {
      printERROR("Erro ao parsear Home: $e");
    }
    return sections;
  }

  List<Map<String, dynamic>> _parseCarouselItems(List<dynamic> items) {
    final List<Map<String, dynamic>> parsed = [];
    for (var item in items) {
      try {
        final renderer = item['musicTwoRowItemRenderer'] ?? 
                          item['musicResponsiveListItemRenderer'] ?? 
                          item['musicNavigationButtonRenderer'];
        if (renderer != null) {
          final parsedItem = _parseItem(renderer);
          if (parsedItem.isNotEmpty) {
            parsed.add(parsedItem);
          }
        }
      } catch (e) {
        continue;
      }
    }
    return parsed;
  }

  Map<String, dynamic> _parseItem(Map<String, dynamic> renderer) {
    final Map<String, dynamic> item = {};
    try {
      // Título
      final title = _getText(renderer['title']);
      if (title.isNotEmpty) item['title'] = title;

      // Thumbnails
      final thumbnails = renderer['thumbnail']?['thumbnails'] as List?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        item['thumbnails'] = thumbnails;
      }

      // ID (videoId, browseId, playlistId)
      final navigate = renderer['navigationEndpoint'];
      if (navigate != null) {
        if (navigate['watchEndpoint'] != null) {
          item['videoId'] = navigate['watchEndpoint']['videoId'];
        } else if (navigate['browseEndpoint'] != null) {
          final browseId = navigate['browseEndpoint']['browseId'] ?? '';
          if (browseId.startsWith('VL')) {
            item['playlistId'] = browseId.substring(2);
          } else {
            item['browseId'] = browseId;
          }
        }
      }

      // Artistas (subtitle)
      final subtitle = renderer['subtitle']?['runs'] as List?;
      if (subtitle != null && subtitle.isNotEmpty) {
        final artistName = subtitle.where((run) => run['text'] != null).map((run) => run['text']).join(' ');
        if (artistName.isNotEmpty) item['artist'] = artistName;
      }

      // ResultType (inferido)
      if (item.containsKey('videoId')) {
        item['resultType'] = 'song';
      } else if (item.containsKey('playlistId')) {
        item['resultType'] = 'playlist';
      } else if (item.containsKey('browseId')) {
        final bid = item['browseId'] as String;
        if (bid.startsWith('MPRE')) item['resultType'] = 'album';
        else if (bid.startsWith('UC')) item['resultType'] = 'artist';
        else item['resultType'] = 'unknown';
      }
    } catch (e) {
      printERROR("Erro ao parsear item: $e");
    }
    return item;
  }

  /// Extrai categorias da busca
  Map<String, dynamic> _parseSearch(Map<String, dynamic> response) {
    final Map<String, dynamic> categories = {
      'Songs': [],
      'Videos': [],
      'Albums': [],
      'Artists': [],
      'Featured playlists': [],
      'Community playlists': [],
    };

    try {
      final contents = response['contents']?['tabbedSearchResultsRenderer']?['tabs'];
      if (contents == null) return categories;

      for (var tab in contents) {
        final tabRenderer = tab['tabRenderer'];
        if (tabRenderer == null) continue;
        final title = _getText(tabRenderer['title']);
        final content = tabRenderer['content']?['sectionListRenderer']?['contents'] as List?;
        if (content == null) continue;

        for (var section in content) {
          final shelf = section['musicShelfRenderer'];
          if (shelf == null) continue;
          final items = _parseShelfItems(shelf);
          if (items.isEmpty) continue;

          // Determina a categoria com base no título da aba
          String categoryKey = 'Songs';
          final lowerTitle = title.toLowerCase();
          if (lowerTitle.contains('song') || lowerTitle.contains('track')) categoryKey = 'Songs';
          else if (lowerTitle.contains('video')) categoryKey = 'Videos';
          else if (lowerTitle.contains('album')) categoryKey = 'Albums';
          else if (lowerTitle.contains('artist')) categoryKey = 'Artists';
          else if (lowerTitle.contains('playlist')) {
            if (lowerTitle.contains('community')) categoryKey = 'Community playlists';
            else categoryKey = 'Featured playlists';
          } else {
            // Fallback: tenta inferir pelo primeiro item
            if (items.isNotEmpty && items.first.containsKey('videoId')) categoryKey = 'Songs';
            else if (items.isNotEmpty && items.first.containsKey('browseId')) categoryKey = 'Albums';
          }

          categories[categoryKey]!.addAll(items);
        }
      }
    } catch (e) {
      printERROR("Erro ao parsear Search: $e");
    }

    // Remove categorias vazias
    categories.removeWhere((key, value) => value.isEmpty);
    return categories;
  }

  List<Map<String, dynamic>> _parseShelfItems(Map<String, dynamic> shelf) {
    final List<Map<String, dynamic>> items = [];
    final contents = shelf['contents'] as List?;
    if (contents == null) return items;

    for (var content in contents) {
      final renderer = content['musicResponsiveListItemRenderer'] ?? 
                       content['musicTwoRowItemRenderer'];
      if (renderer != null) {
        final parsed = _parseItem(renderer);
        if (parsed.isNotEmpty) {
          // Adiciona resultType se não tiver
          if (!parsed.containsKey('resultType')) {
            if (parsed.containsKey('videoId')) parsed['resultType'] = 'song';
            else if (parsed.containsKey('playlistId')) parsed['resultType'] = 'playlist';
            else if (parsed.containsKey('browseId')) {
              final bid = parsed['browseId'] as String;
              if (bid.startsWith('MPRE')) parsed['resultType'] = 'album';
              else if (bid.startsWith('UC')) parsed['resultType'] = 'artist';
            }
          }
          items.add(parsed);
        }
      }
    }
    return items;
  }

  String _getText(dynamic titleObj) {
    if (titleObj == null) return '';
    if (titleObj is String) return titleObj;
    if (titleObj is Map) {
      final runs = titleObj['runs'] as List?;
      if (runs != null) {
        return runs.map((run) => run['text'] ?? '').join();
      }
      return titleObj['text'] ?? '';
    }
    return '';
  }

  // ============================================================
  //  OUTROS MÉTODOS (brutos, sem parse ainda)
  // ============================================================

  Future<Map<String, dynamic>> getSong(String videoId) async {
    final data = Map.from(_context);
    data['videoId'] = videoId;
    data['playbackContext'] = {
      'contentPlaybackContext': {
        'signatureTimestamp': 1,
      }
    };
    return await _post('player', data);
  }

  Future<Map<String, dynamic>> getPlaylist(String playlistId) async {
    final data = Map.from(_context);
    data['browseId'] = 'VL$playlistId';
    return await _post('browse', data);
  }

  Future<Map<String, dynamic>> getAlbum(String albumId) async {
    final data = Map.from(_context);
    data['browseId'] = albumId;
    return await _post('browse', data);
  }

  Future<Map<String, dynamic>> getArtist(String artistId) async {
    final data = Map.from(_context);
    data['browseId'] = artistId;
    return await _post('browse', data);
  }

  Future<Map<String, dynamic>> getWatchPlaylist(String videoId) async {
    final data = Map.from(_context);
    data['videoId'] = videoId;
    data['playlistId'] = 'RDAMVM$videoId';
    data['enablePersistentPlaylistPanel'] = true;
    data['isAudioOnly'] = true;
    return await _post('next', data);
  }
}
