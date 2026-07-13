import 'package:meta/meta.dart';

import '../../../core/models/track.dart';

@immutable
class SearchState {
  final List<Track> results;
  final bool isLoading;
  final String? query;

  const SearchState({
    this.results = const [],
    this.isLoading = false,
    this.query,
  });

  SearchState copyWith({
    List<Track>? results,
    bool? isLoading,
    String? query,
  }) {
    return SearchState(
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      query: query ?? this.query,
    );
  }
}
