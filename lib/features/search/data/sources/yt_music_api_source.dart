import '../../../../core/models/search_result.dart';
import '../../../../core/models/track.dart';
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
      categories: raw,
      continuationParams: continuationParams,
      sourceId: sourceId,
    );
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
      categories: raw,
      continuationParams: newContinuationParams,
      sourceId: sourceId,
    );
  }

  @override
  Future<List<dynamic>> getHomeContent({int limit = 4}) async {
    final home = await _musicServices.getHome(limit: limit);
    return home is List ? home : const [];
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
