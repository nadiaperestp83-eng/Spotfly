import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../../core/providers/providers.dart';
import '../../../models/media_Item_builder.dart';
import '../../../utils/helper.dart';

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
  static const _chartsTimeout = Duration(seconds: 12);

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

    // DIAGNÓSTICO: antes, se todas as fontes (YT/Piped/Jamendo) falhassem,
    // esse erro era descartado aqui e a Home simplesmente ficava em branco
    // sem nenhuma mensagem. Agora o erro real é repassado pra cima —
    // HomeScreenController.loadContentFromNetwork() já tem um try/catch
    // que mostra esse erro num Get.snackbar na tela (não precisa de
    // terminal pra ver).
    if (result.hasError) {
      Error.throwWithStackTrace(
          result.error!, result.stackTrace ?? StackTrace.current);
    }

    // Nesse ponto já garantimos acima (throw) que não há erro, então só
    // sobra o caso de sucesso — mas o tipo de `.value` no Riverpod é
    // sempre `T?` (nullable), daí o `!` pra bater com o retorno
    // `Future<List<dynamic>>` (não nullable) do método.
    return result.value!;
  }

  /// Camada de abstração do Orquestrador para os Charts (Trending + Top
  /// Music Videos), pra Home chamar
  /// `ref.read(homeNotifierProvider.notifier).getCharts()` no lugar de
  /// `_musicServices.getCharts(categoria)` direto. NÃO mexe no
  /// MusicServices original — só embrulha a chamada dele.
  ///
  /// Sempre busca as duas categorias (TR e TMV) juntas. Para cada uma:
  /// 1. Tenta a API interna do YT (`_musicServices.getCharts`).
  /// 2. Se der erro/timeout ou vier vazia, cai pro que já estiver salvo
  ///    em Hive.box("homeScreenData") — sem criar chave nova: só lê
  ///    "quickPicksType"/"quickPicks", que é onde um Chart acaba
  ///    persistido quando ele é o conteúdo ativo da Home (ver
  ///    HomeScreenController.cachedHomeScreenData). Se a categoria não
  ///    bater com o que está cacheado, ela simplesmente não entra no
  ///    resultado (sem dado fabricado).
  ///
  /// Retorno: lista com até 2 entradas, cada uma no MESMO formato que
  /// `_musicServices.getCharts` sempre devolveu por item:
  /// `{'title': ..., 'contents': List<MediaItem>}`.
  Future<List<Map<String, dynamic>>> getCharts() async {
    final results = await Future.wait([
      _getChartCategory('TR', 'Trending'),
      _getChartCategory('TMV', 'Top Music Videos'),
    ]);

    return results.whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>?> _getChartCategory(
      String category, String expectedTitle) async {
    try {
      final musicServices = ref.read(musicServicesProvider);
      final raw =
          await musicServices.getCharts(category).timeout(_chartsTimeout);
      final index = raw.indexWhere((element) =>
          element['title'] == expectedTitle ||
          element['title'] == expectedTitle.toLowerCase());
      if (index != -1 &&
          (raw[index]['contents'] as List?)?.isNotEmpty == true) {
        return raw[index];
      }
    } catch (e) {
      printERROR("Orquestrador: getCharts($category) falhou na API: $e");
    }

    return _chartFromCache(expectedTitle);
  }

  /// Extrai um Chart do que já está salvo em Hive.box("homeScreenData"),
  /// sem criar nenhuma chave nova. Só funciona se o Chart pedido for
  /// exatamente o que estava ativo como quickPicks da Home na última vez
  /// que o cache foi salvo.
  Map<String, dynamic>? _chartFromCache(String expectedTitle) {
    try {
      final homeScreenData = Hive.box("homeScreenData");
      if (homeScreenData.keys.isEmpty) return null;

      final String? cachedTitle = homeScreenData.get("quickPicksType");
      if (cachedTitle == null ||
          cachedTitle.toLowerCase() != expectedTitle.toLowerCase()) {
        return null;
      }

      final List? cachedQuickPicks = homeScreenData.get("quickPicks");
      if (cachedQuickPicks == null || cachedQuickPicks.isEmpty) return null;

      return {
        'title': expectedTitle,
        'contents': cachedQuickPicks
            .map((e) => MediaItemBuilder.fromJson(e))
            .toList(),
      };
    } catch (e) {
      printERROR("Orquestrador: fallback de cache pro Chart falhou: $e");
      return null;
    }
  }
}

final homeNotifierProvider =
    AsyncNotifierProvider<HomeNotifier, List<dynamic>>(HomeNotifier.new);
