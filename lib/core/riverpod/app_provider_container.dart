import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Container global do Riverpod, compartilhado com o ProviderScope raiz
/// (ver main.dart, via UncontrolledProviderScope). Permite que
/// GetxControllers (que não têm WidgetRef) leiam e disparem ações nos
/// providers Riverpod (searchNotifierProvider, homeNotifierProvider etc.)
/// sem precisar converter as telas para ConsumerWidget/ConsumerStatefulWidget.
///
/// Uso típico dentro de um GetxController:
///   final result = await appProviderContainer
///       .read(searchNotifierProvider.notifier)
///       .search(query);
final ProviderContainer appProviderContainer = ProviderContainer();
