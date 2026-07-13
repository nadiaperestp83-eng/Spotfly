import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/track.dart';
import '../../../core/providers/providers.dart';

class SearchNotifier extends AsyncNotifier<List<Track>> {
  Timer? _debounce;
  int _requestId = 0;

  @override
  FutureOr<List<Track>> build() {
    ref.onDispose(() => _debounce?.cancel());
    return [];
  }

  /// Usado pelo campo de busca (debounce evita disparar 1 request por tecla).
  void searchDebounced(String query,
      {Duration delay = const Duration(milliseconds: 400)}) {
    _debounce?.cancel();
    _debounce = Timer(delay, () => search(query));
  }

  Future<void> search(String query) async {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      state = const AsyncData([]);
      return;
    }

    final requestId = ++_requestId;
    state = const AsyncLoading();

    final coordinator = ref.read(searchCoordinatorProvider);
    final result = await AsyncValue.guard(() => coordinator.search(query));

    // Se o usuário já disparou outra busca enquanto esta rodava,
    // descarta esta resposta (evita resultado antigo sobrescrever o novo).
    if (requestId != _requestId) return;

    state = result;
  }

  void clear() {
    _debounce?.cancel();
    _requestId++;
    state = const AsyncData([]);
  }
}

final searchNotifierProvider =
    AsyncNotifierProvider<SearchNotifier, List<Track>>(SearchNotifier.new);

/// Estado do texto digitado, para o campo de busca observar/editar.
final searchQueryProvider = StateProvider<String>((ref) => '');
