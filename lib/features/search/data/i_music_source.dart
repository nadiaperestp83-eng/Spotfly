import '../../../core/models/search_result.dart';
import '../../../core/models/track.dart';

abstract class IMusicSource {
  String get sourceId;

  /// Busca inicial (sem filtro) OU busca de uma aba específica (com
  /// filter/filterParams — mesmo contrato do antigo MusicServices.search).
  /// Fontes que não suportam abas (Piped/Jamendo) devem ignorar
  /// filter/filterParams e devolver tudo dentro da categoria 'Songs'.
  Future<SearchResult> search(
    String query, {
    String? filter,
    String? filterParams,
    int limit = 30,
  });

  /// Continuação (paginação/scroll infinito) de uma aba específica.
  /// Fontes sem suporte a paginação devem devolver um SearchResult vazio
  /// (categories vazio) — o SearchCoordinator trata isso como "sem mais
  /// resultados", sem quebrar a UI.
  Future<SearchResult> searchContinuation(
    Map<String, dynamic> continuationParams, {
    int limit = 10,
  });

  /// Conteúdo da Home já no formato "cru" que HomeScreenController
  /// processa hoje: List<Map<String,dynamic>> com chaves 'title' e
  /// 'contents' (lista de MediaItem/Album/Playlist).
  Future<List<dynamic>> getHomeContent({int limit = 4});

  Future<String> resolveStreamUrl(Track track);
}
