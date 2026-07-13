import 'dart:async';
import 'package:riverpod/riverpod.dart';
import '../domain/search_coordinator.dart';
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
    state = state.copyWith(isLoading: true, query: query, results: []);
    final coordinator = ref.read(searchCoordinatorProvider);

    _sub = coordinator.search(query).listen(
      (tracks) => state = state.copyWith(results: tracks, isLoading: true),
      onDone: () => state = state.copyWith(isLoading: false),
    );
  }
}

final searchNotifierProvider =
    NotifierProvider<SearchNotifier, SearchState>(SearchNotifier.new);

late final searchCoordinatorProvider =
    Provider<SearchCoordinator>((ref) => throw UnimplementedError());
