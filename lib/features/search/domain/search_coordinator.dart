import 'dart:async';

import '../../../core/metadata/i_metadata_provider.dart';
import '../../../core/models/search_result.dart';
import '../../../core/models/track.dart';
import '../data/i_music_source.dart';

class SearchCoordinator {
  final List<IMusicSource> _sources;
  final IMetadataProvider? _metadataProvider;

  static const _sourceTimeout = Duration(seconds: 12);
  static const _enrichTimeout = Duration(seconds: 3);

  // Mapeamento de chaves alternativas para os nomes padronizados
  static const Map<String, String> _keyMapping = {
    'Tracks': 'Songs',
    'Songs': 'Songs',
    'Videos': 'Videos',
    'Albums': 'Albums',
    'Artists': 'Artists',
    'Channels': 'Artists',
    'Featured playlists': 'Featured playlists',
    'Community playlists': 'Community playlists',
    'Playlists': 'Featured playlists', // fallback
  };

  // Lista de chaves que devem ser mantidas (categorias)
  static const List<String> _relevantKeys = [
    'Songs',
    'Videos',
    'Albums',
    'Artists',
    'Featured playlists',
    'Community playlists',
  ];

  SearchCoordinator(this._sources, {IMetadataProvider? metadataProvider})
      : _metadataProvider = metadataProvider;

  Future<SearchResult> search(String query) {
    if (query.trim().isEmpty) {
      return Future.value(const SearchResult(sourceId: 'none'));
    }
    return _runWithFallback((source) => source.search(query));
  }

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
      final result = await source.searchContinuation(params, limit: limit).timeout(_sourceTimeout);
      // Normaliza as chaves do resultado da continuação
      final normalized = _normalizeSearchResult(result);
      return normalized;
    } catch (_) {
      return SearchResult(sourceId: previous.sourceId);
    }
  }

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
          // Normaliza as chaves do resultado antes de retornar
          final normalizedResult = _normalizeSearchResult(result);
          return SearchResult(
            categories: normalizedResult.categories,
            continuationParams: normalizedResult.continuationParams,
            allTracks: enrichedTracks,
            sourceId: source.sourceId,
          );
        }
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        continue;
      }
    }

    if (lastError == null) {
      return const SearchResult(sourceId: 'none');
    }

    Error.throwWithStackTrace(lastError, lastStack ?? StackTrace.current);
  }

  /// Normaliza as chaves de um SearchResult para os nomes padronizados.
  SearchResult _normalizeSearchResult(SearchResult result) {
    if (result.categories.isEmpty) return result;

    final Map<String, dynamic> normalizedMap = {};
    final Map<String, dynamic> normalizedContinuation = {};

    // Percorre as categorias originais
    result.categories.forEach((key, value) {
      final normalizedKey = _keyMapping[key] ?? key;
      // Só mantém se for uma lista (ignora metadados como 'searchEndpoint')
      if (value is List) {
        // Se a chave normalizada já existe, mescla as listas (evitar duplicatas? simplesmente concatena)
        if (normalizedMap.containsKey(normalizedKey) && normalizedMap[normalizedKey] is List) {
          // Mescla sem duplicatas (opcional: usar Set para evitar duplicatas)
          // Vamos manter simples: concatena e depois remove duplicatas? melhor não complicar.
          // Como as fontes são únicas por chamada, raramente haverá duplicata.
          normalizedMap[normalizedKey] = [
            ...normalizedMap[normalizedKey] as List,
            ...(value as List)
          ];
        } else {
          normalizedMap[normalizedKey] = value;
        }

        // Também trata a continuation
        final continuation = result.continuationParams[key];
        if (continuation != null) {
          normalizedContinuation[normalizedKey] = continuation;
        }
      }
    });

    // Filtra para manter apenas as chaves relevantes (opcional, mas garante que não inclua outras)
    // Se quiser manter todas as listas, remova o filtro. Vou manter todas para não perder dados.
    return SearchResult(
      categories: normalizedMap,
      continuationParams: normalizedContinuation,
      allTracks: result.allTracks,
      sourceId: result.sourceId,
    );
  }

  Future<List<Track>> _enrichBatch(List<Track> tracks) async {
    final provider = _metadataProvider;
    if (provider == null || tracks.isEmpty) return tracks;

    return Future.wait(tracks.map((track) async {
      try {
        return await provider.enrich(track).timeout(_enrichTimeout);
      } catch (_) {
        return track;
      }
    }));
  }
}
