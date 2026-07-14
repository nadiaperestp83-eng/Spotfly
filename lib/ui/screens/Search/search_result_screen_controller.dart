import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';

import '../../../core/riverpod/app_provider_container.dart';
import '../../../features/search/state/search_notifier.dart';
import '../../../utils/helper.dart';
import '../Home/home_screen_controller.dart';
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
  //ScrollContollers List
  final Map<String, ScrollController> scrollControllers = {};

  @override
  void onReady() {
    _getInitSearchResult();
    Get.find<HomeScreenController>().whenHomeScreenOnTop();
    super.onReady();
  }

  Future<void> onDestinationSelected(int value,
      {bool ignoreTabCommand = false}) async {
    if (railItems.isEmpty) {
      return;
    }

    isTabTransitionReversed = value > navigationRailCurrentIndex.value;

    isSeparatedResultContentFetced.value = false;
    navigationRailCurrentIndex.value = value;

    if (tabController != null && !ignoreTabCommand) {
      tabController?.animateTo(value);
    }

    // O índice 0 é a visualização "Todos" (All) - ignoramos porque não tem aba específica
    if (value > 0 && value - 1 < railItems.length) {
      final tabName = railItems[value - 1];
      
      // Se já temos dados para essa aba, não recarregamos
      if (separatedResultContent.containsKey(tabName) &&
          separatedResultContent[tabName].isNotEmpty) {
        isSeparatedResultContentFetced.value = true;
        return;
      }

      final itemCount = (tabName == 'Songs' || tabName == 'Videos' || tabName == 'Tracks') ? 25 : 10;
      final filterParams = (resultContent['searchEndpoint'] as Map?)?[tabName] as String?;

      try {
        if (filterParams == null) {
          // Fallback: se não houver filtro específico, usa o que já veio na busca inicial
          separatedResultContent[tabName] =
              List.from(resultContent[tabName] ?? []);
          additionalParamNext[tabName] = {};
        } else {
          final result = await appProviderContainer
              .read(searchNotifierProvider.notifier)
              .searchTab(queryString.value,
                  tabName: tabName,
                  filterParams: filterParams,
                  limit: itemCount);
          separatedResultContent[tabName] = result.categories[tabName] ?? [];
          additionalParamNext[tabName] =
              result.continuationParams[tabName] ?? {};
        }

        final hasContinuation =
            (additionalParamNext[tabName] as Map).isNotEmpty;
        if (hasContinuation) {
          final scrollController = scrollControllers[tabName];
          if (scrollController != null) {
            scrollController.addListener(() {
              double maxScroll = scrollController.position.maxScrollExtent;
              double currentScroll = scrollController.position.pixels;
              if (currentScroll >= maxScroll / 2 &&
                  additionalParamNext[tabName]['additionalParams'] !=
                      '&ctoken=null&continuation=null') {
                if (!continuationInProgress) {
                  continuationInProgress = true;
                  getContinuationContents();
                }
              }
            });
          }
        }
      } catch (e, st) {
        printERROR("Busca da aba '$tabName' falhou: $e");
        printERROR(st.toString());
        separatedResultContent[tabName] = [];
        additionalParamNext[tabName] = {};
        Get.snackbar(
          'Erro na aba "$tabName"',
          e.toString(),
          duration: const Duration(seconds: 10),
          isDismissible: true,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
    isSeparatedResultContentFetced.value = true;
  }

  Future<void> getContinuationContents() async {
    if (navigationRailCurrentIndex.value <= 0) return;
    
    final tabName = railItems[navigationRailCurrentIndex.value - 1];

    if ((additionalParamNext[tabName] as Map?)?.isEmpty ?? true) {
      continuationInProgress = false;
      return;
    }

    try {
      final result = await appProviderContainer
          .read(searchNotifierProvider.notifier)
          .loadMoreTab(tabName);

      separatedResultContent[tabName] =
          result.categories[tabName] ?? separatedResultContent[tabName];
      additionalParamNext[tabName] = result.continuationParams[tabName] ?? {};
      separatedResultContent.refresh();
    } catch (e, st) {
      printERROR("Continuação da aba '$tabName' falhou: $e");
      printERROR(st.toString());
      additionalParamNext[tabName] = {};
      Get.snackbar(
        'Erro ao carregar mais itens ("$tabName")',
        e.toString(),
        duration: const Duration(seconds: 10),
        isDismissible: true,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      continuationInProgress = false;
    }
  }

  void viewAllCallback(String text) {
    final index = railItems.indexOf(text);
    if (index != -1) {
      onDestinationSelected(index + 1);
    }
  }

  Future<void> _getInitSearchResult() async {
    isResultContentFetced.value = false;
    final args = Get.arguments;
    if (args == null) return;

    queryString.value = args;

    final result = await appProviderContainer
        .read(searchNotifierProvider.notifier)
        .search(args);

    // Diagnóstico: verifica se houve erro (AsyncValue)
    final asyncState = appProviderContainer.read(searchNotifierProvider);
    if (asyncState.hasError) {
      printERROR("Busca inicial falhou: ${asyncState.error}");
      Get.snackbar(
        'Erro na busca',
        asyncState.error.toString(),
        duration: const Duration(seconds: 10),
        isDismissible: true,
        snackPosition: SnackPosition.BOTTOM,
      );
    }

    // 🔥 CORREÇÃO: Aceita dinamicamente todas as chaves não vazias
    final allKeys = <String>[];
    for (var key in result.categories.keys) {
      final content = result.categories[key];
      if (content is List && content.isNotEmpty) {
        allKeys.add(key);
      }
    }

    // Se não encontrou nenhuma chave com conteúdo, tenta um fallback com nomes comuns
    if (allKeys.isEmpty) {
      final fallbackKeys = [
        "Songs",
        "Tracks",
        "Videos",
        "Albums",
        "Featured playlists",
        "Community playlists",
        "Playlists",
        "Artists",
        "Channels"
      ];
      for (var key in fallbackKeys) {
        if (result.categories.containsKey(key) &&
            (result.categories[key] as List?)?.isNotEmpty == true) {
          allKeys.add(key);
        }
      }
    }

    // Se ainda assim não houver nada, pelo menos exibe as chaves que existem (mesmo vazias)
    if (allKeys.isEmpty) {
      // Pega todas as chaves disponíveis, mesmo que vazias, para não ficar tela em branco
      allKeys.addAll(result.categories.keys);
    }

    railItems.value = allKeys;

    // Atualiza o resultContent com todas as categorias
    resultContent.value = Map<String, dynamic>.from(result.categories);

    // Cálculo da altura do rail (opcional)
    final len = railItems.where((element) => element.toLowerCase().contains("playlist")).length;
    final calH = 30 + (railItems.length + 1 - len) * 123 + len * 150.0;
    railitemHeight.value = calH >= railitemHeight.value ? calH : railitemHeight.value;

    // Cria ScrollControllers para cada item
    for (String item in railItems) {
      if (!scrollControllers.containsKey(item)) {
        scrollControllers[item] = ScrollController();
      }
    }

    // Configuração para bottom nav / desktop
    if (GetPlatform.isDesktop ||
        Get.find<SettingsScreenController>().isBottomNavBarEnabled.isTrue) {
      for (var element in railItems) {
        if (!separatedResultContent.containsKey(element)) {
          separatedResultContent[element] = [];
        }
      }
      if (tabController == null) {
        tabController = TabController(length: railItems.length + 1, vsync: this);
      } else {
        tabController?.dispose();
        tabController = TabController(length: railItems.length + 1, vsync: this);
      }
      tabController?.animation?.addListener(() {
        int indexChange = tabController!.offset.round();
        int index = tabController!.index + indexChange;
        if (index != navigationRailCurrentIndex.value) {
          onDestinationSelected(index, ignoreTabCommand: true);
        }
      });
    }

    isResultContentFetced.value = true;
  }

  void onSort(SortType sortType, bool isAscending, String title) {
    // 🔥 Normaliza o título para comparação
    final lowerTitle = title.toLowerCase();
    final contentList = separatedResultContent[title];
    if (contentList == null || contentList.isEmpty) return;

    if (lowerTitle.contains("song") || lowerTitle.contains("track")) {
      final list = List.from(contentList);
      sortSongsNVideos(list, sortType, isAscending);
      separatedResultContent[title] = list;
    } else if (lowerTitle.contains("playlist")) {
      final list = List.from(contentList);
      sortPlayLists(list, sortType, isAscending);
      separatedResultContent[title] = list;
    } else if (lowerTitle.contains("artist") || lowerTitle.contains("channel")) {
      final list = List.from(contentList);
      sortArtist(list, sortType, isAscending);
      separatedResultContent[title] = list;
    } else if (lowerTitle.contains("album")) {
      final list = List.from(contentList);
      sortAlbumNSingles(list, sortType, isAscending);
      separatedResultContent[title] = list;
    } else if (lowerTitle.contains("video")) {
      final list = List.from(contentList);
      sortSongsNVideos(list, sortType, isAscending);
      separatedResultContent[title] = list;
    }
  }

  @override
  void onClose() {
    for (String item in railItems) {
      scrollControllers[item]?.dispose();
    }
    tabController?.dispose();
    Get.find<HomeScreenController>().whenHomeScreenOnTop();
    super.onClose();
  }
}
