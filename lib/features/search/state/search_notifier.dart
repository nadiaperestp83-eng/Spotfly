import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/search_result.dart';
import '../../../core/providers/providers.dart';

class SearchNotifier extends AsyncNotifier<SearchResult> {
  Timer? _debounce;
  int _requestId = 0;

  @override
  FutureOr<SearchResult> build() {
    ref.onDispose(() => _debounce?.cancel());
    return const SearchResult(sourceId: 'none');
  }

  /// Usado pelo campo de busca (debounce evita disparar 1 request por tecla).
  void searchDebounced(String query,
      {Duration delay = const Duration(milliseconds: 400)}) {
    _debounce?.cancel();
    _debounce = Timer(delay, () => search(query));
  }

  /// Busca inicial — substitui musicServices.search(query) dentro de
  /// SearchResultScreenController._getInitSearchResult().
  Future<SearchResult> search(String query) async {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      const empty = SearchResult(sourceId: 'none');
      state = const AsyncData(empty);
      return empty;
    }

    final requestId = ++_requestId;
    state = const AsyncLoading();

    final coordinator = ref.read(searchCoordinatorProvider);
    final result = await AsyncValue.guard(() => coordinator.search(query));

    // Se o usuário já disparou outra busca enquanto esta rodava, descarta
    // esta resposta (evita resultado antigo sobrescrever o novo).
    if (requestId != _requestId) {
      return state.valueOrNull ?? const SearchResult(sourceId: 'none');
    }

    state = result;

    // DIAGNÓSTICO: antes, se todas as fontes falhassem, esse erro era
    // descartado aqui e a tela de busca só mostrava "categorias: nenhuma"
    // sem dizer o motivo. Agora o erro real é repassado pra cima —
    // SearchResultScreenController._getInitSearchResult() captura isso
    // num try/catch e mostra a mensagem real no diálogo de debug.
    if (result.hasError) {
      Error.throwWithStackTrace(
          result.error!, result.stackTrace ?? StackTrace.current);
    }

    return result.value;
  }

  /// Busca de uma aba (Songs/Videos/Albums/...) — substitui a chamada de
  /// musicServices.search(query, filter: ...) dentro de
  /// onDestinationSelected().
  Future<SearchResult> searchTab(
    String query, {
    required String tabName,
    required String filterParams,
    int limit = 25,
  }) async {
    final coordinator = ref.read(searchCoordinatorProvider);
    final result = await coordinator.searchTab(
      query,
      tabName: tabName,
      filterParams: filterParams,
      limit: limit,
    );

    final current = state.valueOrNull ?? const SearchResult(sourceId: 'none');
    final merged = SearchResult(
      categories: {...current.categories, ...result.categories},
      continuationParams: {
        ...current.continuationParams,
        ...result.continuationParams,
      },
      allTracks: current.allTracks,
      sourceId: result.sourceId,
    );

    state = AsyncData(merged);
    return merged;
  }

  /// Continuação (scroll infinito) de uma aba — substitui
  /// musicServices.getSearchContinuation(...) dentro de
  /// getContinuationContents().
  Future<SearchResult> loadMoreTab(String tabName, {int limit = 10}) async {
    final current = state.valueOrNull ?? const SearchResult(sourceId: 'none');
    final coordinator = ref.read(searchCoordinatorProvider);
    final more = await coordinator.searchContinuation(current, tabName, limit: limit);

    final newItems = more.categories[tabName];
    if (newItems == null) return current;

    final mergedList = [...(current.categories[tabName] as List? ?? []), ...newItems];

    final merged = SearchResult(
      categories: {...current.categories, tabName: mergedList},
      continuationParams: {
        ...current.continuationParams,
        ...more.continuationParams,
      },
      allTracks: current.allTracks,
      sourceId: current.sourceId,
    );

    state = AsyncData(merged);
    return merged;
  }

  void clear() {
    _debounce?.cancel();
    _requestId++;
    state = const AsyncData(SearchResult(sourceId: 'none'));
  }
}

final searchNotifierProvider =
    AsyncNotifierProvider<SearchNotifier, SearchResult>(SearchNotifier.new);

/// Estado do texto digitado, para o campo de busca observar/editar.
final searchQueryProvider = StateProvider<String>((ref) => '');
