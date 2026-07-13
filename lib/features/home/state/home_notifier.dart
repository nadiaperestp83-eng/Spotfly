import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/home_section.dart';
import '../../../core/providers/providers.dart';

class HomeNotifier extends AsyncNotifier<List<HomeSection>> {
  @override
  FutureOr<List<HomeSection>> build() {
    return ref.read(searchCoordinatorProvider).getHome();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(searchCoordinatorProvider).getHome());
  }
}

final homeNotifierProvider =
    AsyncNotifierProvider<HomeNotifier, List<HomeSection>>(HomeNotifier.new);
