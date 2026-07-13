import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import 'search_state.dart';

class SearchNotifier extends Notifier<SearchState> {
  StreamSubscription? _sub;

  @override
  SearchState build() {
    ref.onDispose(() => _sub?.cancel());
    return const SearchState();
  }

  void search(String query) {
    _sub?.cancel();

    if (query.trim().isEmpty) {
      state = const SearchState();
      return;
    }

    state = state.copyWith(isLoading: true, query: query, results: []);
    final coordinator = ref.read(searchCoordinatorProvider);

    _sub = coordinator.search(query).listen(
      (tracks) => state = state.copyWith(results: tracks, isLoading: true),
      onDone: () => state = state.copyWith(isLoading: false),
    );
  }

  void clear() {
    _sub?.cancel();
    state = const SearchState();
  }
}

final searchNotifierProvider =
    NotifierProvider<SearchNotifier, SearchState>(SearchNotifier.new);
