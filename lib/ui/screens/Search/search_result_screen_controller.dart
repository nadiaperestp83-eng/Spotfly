import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';

import '../../../core/models/search_result.dart';
import '../../../core/riverpod/app_provider_container.dart';
import '../../../features/search/state/search_notifier.dart';
import '../../../utils/helper.dart';
import '../Home/home_screen_controller.dart';
import '/ui/widgets/snackbar.dart';
import '/ui/widgets/sort_widget.dart';

class SearchResultScreenController extends GetxController
    with GetTickerProviderStateMixin {
  final navigationRailCurrentIndex = 0.obs;
  final isResultContentFetced = false.obs;
  final isSeparatedResultContentFetced = false.obs;
  final resultContent = <String, dynamic>{}.obs;
  final separatedResultContent = <String, dynamic>{}.obs;
  final queryString = ''.obs;
  final railItems = <String>[].obs;
  final railitemHeight = Get.size.height.obs;
  final additionalParamNext = {};
  bool continuationInProgress = false;
  TabController? tabController;
  bool isTabTransitionReversed = false;
  final Map<String, ScrollController> scrollControllers = {};

  static const Map<String, String> keyMapping = {
    'Tracks': 'Songs',
    'Track': 'Songs',
    'Song': 'Songs',
    'Songs': 'Songs',
    'Video': 'Videos',
    'Videos': 'Videos',
    'Album': 'Albums',
    'Albums': 'Albums',
    'Artist': 'Artists',
    'Artists': 'Artists',
    'Channel': 'Artists',
    'Channels': 'Artists',
    'Featured playlist': 'Featured playlists',
    'Featured playlists': 'Featured playlists',
    'Community playlist': 'Community playlists',
    'Community playlists': 'Community playlists',
    'Playlist': 'Featured playlists',
    'Playlists': 'Featured playlists',
  };

  /// Normaliza uma chave de categoria vinda da fonte (YT Music/Piped/
  /// Jamendo) para o nome padrão usado pela UI. Além do keyMapping direto,
  /// tenta um fallback case-insensitive antes de desistir e manter a chave
  /// original — assim nenhuma categoria nova/renomeada é silenciosamente
  /// descartada.
  String _normalizeKey(String rawKey) {
    if (keyMapping.containsKey(rawKey)) return keyMapping[rawKey]!;
    final lower = rawKey.trim().toLowerCase();
    for (final entry in keyMapping.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return rawKey;
  }

  @override
  void onReady() {
    _getInitSearchResult();
    Get.find<HomeScreenController>().whenHomeScreenOnTop();
    super.onReady();
  }

  Future<void> onDestinationSelected(int value, {bool ignoreTabCommand = false}) async {
    if (railItems.isEmpty) return;

    isTabTransitionReversed = value > navigationRailCurrentIndex.value;
    isSeparatedResultContentFetced.value = false;
    navigationRailCurrentIndex.value = value;

    if (tabController != null && !ignoreTabCommand) {
      tabController?.animateTo(value);
    }

    if (value > 0) {
      final tabName = railItems[value - 1];
      // Carrega se não existir ou se estiver vazia
      if (!separatedResultContent.containsKey(tabName) || separatedResultContent[tabName].isEmpty) {
        final itemCount = (tabName == 'Songs' || tabName == 'Videos') ? 25 : 10;
        final filterParams = (resultContent['searchEndpoint'] as Map?)?[tabName] as String?;

        try {
          if (filterParams == null) {
            separatedResultContent[tabName] = List.from(resultContent[tabName] ?? []);
            additionalParamNext[tabName] = {};
          } else {
            final result = await appProviderContainer
                .read(searchNotifierProvider.notifier)
                .searchTab(queryString.value, tabName: tabName, filterParams: filterParams, limit: itemCount);
            separatedResultContent[tabName] = result.categories[tabName] ?? [];
            additionalParamNext[tabName] = result.continuationParams[tabName] ?? {};
          }
          
          // Adiciona listener para scroll se houver paginação
          if ((additionalParamNext[tabName] as Map).isNotEmpty) {
            final scrollController = scrollControllers[tabName];
            scrollController?.addListener(() {
              if (scrollController.position.pixels >= scrollController.position.maxScrollExtent / 2) {
                if (!continuationInProgress) {
                  continuationInProgress = true;
                  getContinuationContents();
                }
              }
            });
          }
        } catch (e) {
          printERROR("Erro na aba '$tabName': $e");
          if (Get.context != null) {
            ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
                Get.context!, "Erro na aba '$tabName': $e",
                size: SanckBarSize.MEDIUM));
          }
        }
      }
    }
    isSeparatedResultContentFetced.value = true;
  }

  Future<void> getContinuationContents() async {
    final tabName = railItems[navigationRailCurrentIndex.value - 1];
    if ((additionalParamNext[tabName] as Map?)?.isEmpty ?? true) {
      continuationInProgress = false;
      return;
    }
    try {
      final result = await appProviderContainer.read(searchNotifierProvider.notifier).loadMoreTab(tabName);
      separatedResultContent[tabName] = result.categories[tabName] ?? separatedResultContent[tabName];
      additionalParamNext[tabName] = result.continuationParams[tabName] ?? {};
      separatedResultContent.refresh();
    } catch (e) {
      printERROR("Erro ao carregar mais itens: $e");
      if (Get.context != null) {
        ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
            Get.context!, "Erro ao carregar mais itens: $e",
            size: SanckBarSize.MEDIUM));
      }
    } finally {
      continuationInProgress = false;
    }
  }

  void viewAllCallback(String text) {
    if (railItems.contains(text)) {
      onDestinationSelected(railItems.indexOf(text) + 1);
    }
  }

  Future<void> _getInitSearchResult() async {
    isResultContentFetced.value = false;
    final args = Get.arguments;
    if (args == null) return;
    queryString.value = args;

    String? errorMessage;
    SearchResult result;
    try {
      result = await appProviderContainer
          .read(searchNotifierProvider.notifier)
          .search(args);
    } catch (e) {
      // DIAGNÓSTICO: antes esse erro sumia (a tela só mostrava
      // "categorias: nenhuma", sem dizer o motivo real). Agora a
      // mensagem de exceção de verdade (rede, parsing, todas as fontes
      // falharam, etc.) é guardada pra aparecer no diálogo de debug logo
      // abaixo.
      printERROR("Erro na busca inicial: $e");
      errorMessage = e.toString();
      result = const SearchResult(sourceId: 'none');
    }

    // Guarda as chaves cruas retornadas pela fonte, antes de qualquer
    // normalização, só para fins de debug (dialog abaixo).
    final rawKeys = result.categories.keys.toList();

    // Normalização sem descartar chaves vazias, tolerante a variações de
    // nome (singular/plural, maiúsculas/minúsculas) via _normalizeKey.
    Map<String, dynamic> normalizedMap = {};
    result.categories.forEach((key, value) {
      // 'searchEndpoint' é metadado interno (params dos chips), não uma
      // categoria de conteúdo — não deve virar aba nem contar como "lista".
      if (key == 'searchEndpoint') {
        normalizedMap[key] = value;
        return;
      }
      final normalizedKey = _normalizeKey(key);
      if (normalizedMap.containsKey(normalizedKey) && value is List && normalizedMap[normalizedKey] is List) {
        normalizedMap[normalizedKey] = [...normalizedMap[normalizedKey], ...value];
      } else {
        normalizedMap[normalizedKey] = value;
      }
    });

    // Lista de categorias esperadas
    final List<String> targetKeys = ["Songs", "Videos", "Albums", "Artists", "Featured playlists", "Community playlists"];

    // Adiciona as chaves que existem no resultado
    railItems.value = targetKeys.where((key) => normalizedMap.containsKey(key)).toList();

    // Se nenhuma das chaves esperadas foi encontrada, adiciona o que vier de
    // listas (fallback: mostra qualquer categoria com conteúdo, mesmo que o
    // nome não seja um dos esperados, em vez de sumir com o resultado).
    if (railItems.isEmpty) {
      railItems.value = normalizedMap.keys
          .where((key) => key != 'searchEndpoint' && normalizedMap[key] is List)
          .toList();
    }

    resultContent.value = normalizedMap;

    for (String item in railItems) {
      scrollControllers[item] = ScrollController();
      separatedResultContent[item] = normalizedMap[item] ?? [];
    }

    if (GetPlatform.isDesktop || Get.find<SettingsScreenController>().isBottomNavBarEnabled.isTrue) {
      tabController = TabController(length: railItems.length + 1, vsync: this);
    }

    isResultContentFetced.value = true;

    _maybeShowDebugCategoriesDialog(rawKeys, normalizedMap, errorMessage);
  }

  /// Debug UI: se a busca não gerou nenhuma aba, se Songs/Videos vieram
  /// vazios, OU se houve um erro real na busca, mostra um diálogo com as
  /// chaves exatas recebidas da fonte e (agora) a mensagem de erro de
  /// verdade. Ajuda a diagnosticar rapidamente sem precisar de terminal.
  void _maybeShowDebugCategoriesDialog(List<String> rawKeys,
      Map<String, dynamic> normalizedMap, String? errorMessage) {
    final songsEmpty = (normalizedMap['Songs'] is! List) || (normalizedMap['Songs'] as List).isEmpty;
    final videosEmpty = (normalizedMap['Videos'] is! List) || (normalizedMap['Videos'] as List).isEmpty;

    if (errorMessage != null || railItems.isEmpty || songsEmpty || videosEmpty) {
      final keysDescription = rawKeys.isEmpty ? '(nenhuma)' : rawKeys.join(', ');
      final errorSection = errorMessage != null
          ? '\n\nERRO REAL (antes ficava escondido):\n$errorMessage'
          : '';
      Get.defaultDialog(
        title: 'Debug: categorias da busca',
        middleText:
            'O servidor retornou as seguintes categorias: $keysDescription\n\n'
            'Abas exibidas: ${railItems.isEmpty ? '(nenhuma)' : railItems.join(', ')}'
            '$errorSection',
        textConfirm: 'OK',
        onConfirm: () => Get.back(),
      );
    }
  }

  void onSort(SortType sortType, bool isAscending, String title) {
    if (!separatedResultContent.containsKey(title)) return;
    final list = separatedResultContent[title].toList();
    
    final lowerTitle = title.toLowerCase();
    if (lowerTitle.contains("song") || lowerTitle.contains("track")) sortSongsNVideos(list, sortType, isAscending);
    else if (lowerTitle.contains("playlist")) sortPlayLists(list, sortType, isAscending);
    else if (lowerTitle.contains("artist") || lowerTitle.contains("channel")) sortArtist(list, sortType, isAscending);
    else if (lowerTitle.contains("album")) sortAlbumNSingles(list, sortType, isAscending);
    
    separatedResultContent[title] = list;
    separatedResultContent.refresh();
  }

  @override
  void onClose() {
    for (var controller in scrollControllers.values) controller.dispose();
    Get.find<HomeScreenController>().whenHomeScreenOnTop();
    tabController?.dispose();
    super.onClose();
  }
}
