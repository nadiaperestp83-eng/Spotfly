import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';

/// O cache Hive ("homeScreenData") continua sendo lido primeiro por
/// HomeScreenController.loadContentFromDb() — isso não muda. Este
/// Notifier só substitui a ORIGEM da chamada de rede: em vez de
/// `_musicServices.getHome()` direto, HomeScreenController passa a
/// chamar `fetchHomeContent()`, que roteia pelo Orquestrador
/// (fallback YT -> Piped -> Jamendo). O retorno continua no mesmo
/// formato List<Map<String,dynamic>> de sempre, então toda a lógica de
/// Quick Picks/Charts/BOLI dentro de HomeScreenController não muda
/// nem uma linha.
class HomeNotifier extends AsyncNotifier<List<dynamic>> {
  @override
  FutureOr<List<dynamic>> build() {
    return const [];
  }

  /// Usado por HomeScreenController.loadContentFromNetwork() no lugar de
  /// `_musicServices.getHome(limit: ...)`.
  Future<List<dynamic>> fetchHomeContent({int limit = 4}) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
        () => ref.read(searchCoordinatorProvider).getHome(limit: limit));
    state = result;
    return result.valueOrNull ?? const [];
  }
}

final homeNotifierProvider =
    AsyncNotifierProvider<HomeNotifier, List<dynamic>>(HomeNotifier.new);
