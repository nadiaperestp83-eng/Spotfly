import 'dart:async';

import '../../../core/metadata/i_metadata_provider.dart';
import '../../../core/models/search_result.dart';
import '../../../core/models/track.dart';
import '../data/i_music_source.dart';

/// Orquestrador central. Não sabe COMO cada fonte funciona (HTTP,
/// scraping, SDK...), só conhece a interface IMusicSource.
///
/// Estratégia: fallback automático e sequencial, na ordem definida em
/// musicSourcesProvider (ver core/providers/providers.dart). Tenta a
/// fonte 1; se der erro/timeout/vazio, tenta a fonte 2; e assim por
/// diante. Retorna assim que a primeira fonte responder com conteúdo.
///
/// A UI (via SearchNotifier/HomeNotifier) recebe sempre um SearchResult
/// ou uma List<dynamic> no MESMO formato que a MusicServices antiga já
/// devolvia — a troca de fonte é invisível pra UI.
class SearchCoordinator {
  final List<IMusicSource> _sources;
  final IMetadataProvider? _metadataProvider;

  static const _sourceTimeout = Duration(seconds: 12);
  static const _enrichTimeout = Duration(seconds: 3);

  SearchCoordinator(this._sources, {IMetadataProvider? metadataProvider})
      : _metadataProvider = metadataProvider;

  /// Busca inicial (sem filtro) — substitui musicServices.search(query).
  Future<SearchResult> search(String query) {
    if (query.trim().isEmpty) {
      return Future.value(const SearchResult(sourceId: 'none'));
    }
    return _runWithFallback((source) => source.search(query));
  }

  /// Busca de uma aba/categoria específica — substitui
  /// musicServices.search(query, filter: ..., filterParams: ...).
  Future<SearchResult> searchTab(
    String query, {
    required String tabName,
    required String filterParams,
    int limit = 25,
  }) {
    return _runWithFallback((source) => source.search(
          query,
          filter: tabName.replaceAll(' ', '_').toLowerCase(),
          filterParams: filterParams,
          limit: limit,
        ));
  }

  /// Continuação (scroll infinito) de uma aba específica — substitui
  /// musicServices.getSearchContinuation(...). Precisa do SearchResult
  /// anterior pra saber qual fonte respondeu e quais parâmetros usar.
  Future<SearchResult> searchContinuation(
    SearchResult previous,
    String tabName, {
    int limit = 10,
  }) async {
    final params = previous.continuationParams[tabName];
    if (params == null) {
      return SearchResult(sourceId: previous.sourceId);
    }

    final source = _sources.firstWhere(
      (s) => s.sourceId == previous.sourceId,
      orElse: () => _sources.first,
    );

    try {
      return await source.searchContinuation(params, limit: limit).timeout(_sourceTimeout);
    } catch (_) {
      return SearchResult(sourceId: previous.sourceId);
    }
  }

  /// Mesma estratégia de fallback sequencial, usada pela Home. Devolve
  /// o conteúdo já no formato "cru" (List<Map<String,dynamic>>) que
  /// HomeScreenController processa hoje.
  Future<List<dynamic>> getHome({int limit = 4}) async {
    Object? lastError;
    StackTrace? lastStack;

    for (final source in _sources) {
      try {
        final content = await source.getHomeContent(limit: limit).timeout(_sourceTimeout);
        if (content.isNotEmpty) return content;
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        continue;
      }
    }

    if (lastError == null) return const [];
    Error.throwWithStackTrace(lastError, lastStack ?? StackTrace.current);
  }

  Future<SearchResult> _runWithFallback(
    Future<SearchResult> Function(IMusicSource source) attempt,
  ) async {
    Object? lastError;
    StackTrace? lastStack;

    for (final source in _sources) {
      try {
        final result = await attempt(source).timeout(_sourceTimeout);
        if (!result.isEmpty) {
          final enrichedTracks = await _enrichBatch(result.allTracks);
          return SearchResult(
            categories: result.categories,
            continuationParams: result.continuationParams,
            allTracks: enrichedTracks,
            sourceId: source.sourceId,
          );
        }
        // Fonte respondeu mas não achou nada: tenta a próxima mesmo assim.
      } catch (e, st) {
        // Fonte falhou (rede, timeout, parsing...). Nunca propaga aqui —
        // isso é o que evita o loop/travamento. Só guarda pra decidir
        // depois se TODAS falharam.
        lastError = e;
        lastStack = st;
        continue;
      }
    }

    if (lastError == null) {
      // Todas as fontes responderam, nenhuma achou nada: resultado
      // legítimo vazio, não é erro.
      return const SearchResult(sourceId: 'none');
    }

    // Todas as fontes falharam de fato: propaga o último erro para o
    // AsyncNotifier, que vai virar AsyncError na UI (nunca fica preso
    // em loading).
    Error.throwWithStackTrace(lastError, lastStack ?? StackTrace.current);
  }

  Future<List<Track>> _enrichBatch(List<Track> tracks) async {
    final provider = _metadataProvider;
    if (provider == null || tracks.isEmpty) return tracks;

    return Future.wait(tracks.map((track) async {
      try {
        return await provider.enrich(track).timeout(_enrichTimeout);
      } catch (_) {
        return track; // mantém a versão "crua" — enriquecimento é best-effort
      }
    }));
  }
}
