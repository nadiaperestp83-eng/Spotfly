import 'dart:async';

import '../../../core/metadata/i_metadata_provider.dart';
import '../../../core/models/search_result.dart';
import '../../../core/models/track.dart';
import '../data/i_music_source.dart';

/// Orquestrador central com fallback automático.
class SearchCoordinator {
  final List<IMusicSource> _sources;
  final IMetadataProvider? _metadataProvider;

  static const _sourceTimeout = Duration(seconds: 12);
  static const _enrichTimeout = Duration(seconds: 3);

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
      return await source.searchContinuation(params, limit: limit).timeout(_sourceTimeout);
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
          
          // 🔥 Garante que continuationParams seja do tipo correto
          final Map<String, Map<String, dynamic>> normalizedContinuation = {};
          result.continuationParams.forEach((key, value) {
            if (value is Map<String, dynamic>) {
              normalizedContinuation[key] = value;
            } else {
              normalizedContinuation[key] = {'raw': value};
            }
          });

          return SearchResult(
            categories: result.categories,
            continuationParams: normalizedContinuation,
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
