import 'package:audio_service/audio_service.dart';

import '../../../../core/models/search_result.dart';
import '../../../../core/models/track.dart';
import '../../../../models/album.dart';
import '../../../../models/artist.dart';
import '../../../../models/media_Item_builder.dart';
import '../../../../models/playlist.dart';
import '../../../../services/music_service.dart';
import '../i_music_source.dart';

/// Fonte "youtube" do Orquestrador — wrapper do MusicServices existente
/// (API interna do YT Music), que já tem categorias (Songs/Videos/
/// Albums/Artists/Playlists), paginação e Home ricos. Nenhuma tela deve
/// instanciar/chamar isso diretamente: só o SearchCoordinator conhece
/// esta classe (via musicSourcesProvider).
class YtMusicApiSource implements IMusicSource {
  final MusicServices _musicServices;

  YtMusicApiSource(this._musicServices);

  @override
  String get sourceId => 'youtube';

  @override
  Future<SearchResult> search(
    String query, {
    String? filter,
    String? filterParams,
    int limit = 30,
  }) async {
    final raw = await _musicServices.search(
      query,
      filter: filter,
      limit: limit,
      filterParams: filterParams,
    );

    final continuationParams = <String, Map<String, dynamic>>{};
    final params = raw['params'];
    if (filter != null && params != null) {
      final category = params['category'] as String?;
      if (category != null) {
        continuationParams[category] = Map<String, dynamic>.from(params);
      }
    }

    return SearchResult(
      categories: _typedCategories(raw),
      continuationParams: continuationParams,
      sourceId: sourceId,
    );
  }

  /// list_widget.dart faz cast/acesso direto nos itens de cada categoria
  /// (`items[index] as MediaItem`, `playlists[index].title`,
  /// `artists[index].name`, `albums[index].title`) — precisa dos objetos
  /// tipados de verdade, não de Map cru. Sem essa conversão, o cast falha
  /// silenciosamente em release e a UI mostra uma caixa cinza vazia no
  /// lugar de cada item.
  Map<String, dynamic> _typedCategories(Map<String, dynamic> raw) {
    final result = <String, dynamic>{};
    raw.forEach((key, value) {
      if (key == 'searchEndpoint' || key == 'params') {
        result[key] = value;
        return;
      }
      if (value is! List) {
        result[key] = value;
        return;
      }

      if (key == 'Songs' || key == 'Videos') {
        result[key] = value
            .map((e) => _safeConvert(() =>
                MediaItemBuilder.fromJson(Map<String, dynamic>.from(e as Map))))
            .whereType<MediaItem>()
            .toList();
      } else if (key == 'Artists') {
        result[key] = value
            .map((e) => _safeConvert(
                () => Artist.fromJson(Map<String, dynamic>.from(e as Map))))
            .whereType<Artist>()
            .toList();
      } else if (key == 'Featured playlists' || key == 'Community playlists') {
        result[key] = value
            .map((e) => _safeConvert(
                () => Playlist.fromJson(Map<String, dynamic>.from(e as Map))))
            .whereType<Playlist>()
            .toList();
      } else if (key == 'Albums' || key == 'Singles') {
        result[key] = value
            .map((e) => _safeConvert(
                () => Album.fromJson(Map<String, dynamic>.from(e as Map))))
            .whereType<Album>()
            .toList();
      } else {
        result[key] = value;
      }
    });
    return result;
  }

  T? _safeConvert<T>(T Function() convert) {
    try {
      return convert();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SearchResult> searchContinuation(
    Map<String, dynamic> continuationParams, {
    int limit = 10,
  }) async {
    if (continuationParams.isEmpty) {
      return const SearchResult(sourceId: 'youtube');
    }

    final raw = await _musicServices.getSearchContinuation(
      continuationParams,
      limit: limit,
    );

    final newContinuationParams = <String, Map<String, dynamic>>{};
    final params = raw['params'];
    if (params != null) {
      final category = params['category'] as String?;
      if (category != null) {
        newContinuationParams[category] = Map<String, dynamic>.from(params);
      }
    }

    return SearchResult(
      categories: _typedCategories(raw),
      continuationParams: newContinuationParams,
      sourceId: sourceId,
    );
  }

  @override
  Future<List<dynamic>> getHomeContent({int limit = 4}) async {
    final home = await _musicServices.getHome(limit: limit);
    if (home is! List) return const [];

    final result = <Map<String, dynamic>>[];
    for (final section in home) {
      if (section is! Map) continue;
      final rawContents = section['contents'];
      if (rawContents is! List || rawContents.isEmpty) continue;

      final mediaItems = <MediaItem>[];
      for (final item in rawContents) {
        try {
          if (item is Map && item['videoId'] != null) {
            mediaItems.add(MediaItemBuilder.fromJson(Map<String, dynamic>.from(item)));
          }
        } catch (_) {
          continue;
        }
      }
      if (mediaItems.isNotEmpty) {
        result.add({'title': section['title'] ?? '', 'contents': mediaItems});
      }
    }
    return result;
  }

  @override
  Future<String> resolveStreamUrl(Track track) {
    // A fonte "youtube" não passa por aqui: músicas dela tocam pelo
    // pipeline de player legado (baseado no videoId do MediaItem), não
    // pelo PlaybackResolver genérico. Ver track_media_item_mapper.dart.
    throw UnsupportedError(
        'resolveStreamUrl não é usado para a fonte "youtube" nesta integração.');
  }
}
