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
  final Map<String, ScrollController> scrollControllers = {};

  @override
  void onReady() {
    _getInitSearchResult();
    Get.find<HomeScreenController>().whenHomeScreenOnTop();
    super.onReady();
  }

  Future<void> onDestinationSelected(int value,
      {bool ignoreTabCommand = false}) async {
    if (railItems.isEmpty) return;

    isTabTransitionReversed = value > navigationRailCurrentIndex.value;
    isSeparatedResultContentFetced.value = false;
    navigationRailCurrentIndex.value = value;

    if (tabController != null && !ignoreTabCommand) {
      tabController?.animateTo(value);
    }

    if (value > 0 &&
        (!separatedResultContent.containsKey(railItems[value - 1]) ||
            separatedResultContent[railItems[value - 1]].isEmpty)) {
      final tabName = railItems[value - 1];
      final itemCount = (tabName == 'Songs' || tabName == 'Videos') ? 25 : 10;
      final filterParams =
          (resultContent['searchEndpoint'] as Map?)?[tabName] as String?;

      try {
        if (filterParams == null) {
          // Fallback: usa os dados já carregados na busca inicial
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
          scrollController!.addListener(() {
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
    onDestinationSelected(railItems.indexOf(text) + 1);
  }

  Future<void> _getInitSearchResult() async {
    isResultContentFetced.value = false;
    final args = Get.arguments;
    if (args == null) return;

    queryString.value = args;

    final result = await appProviderContainer
        .read(searchNotifierProvider.notifier)
        .search(args);

    // Log para diagnóstico
    printINFO("Chaves recebidas: ${result.categories.keys}");
    printINFO("Conteúdo: ${result.categories}");

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

    // 🔥 CORREÇÃO: filtra apenas chaves cujo valor é uma List não vazia
    // Isso exclui "searchEndpoint" e outros metadados que sejam Map
    final allKeys = result.categories.keys
        .where((key) => result.categories[key] is List &&
            (result.categories[key] as List).isNotEmpty)
        .toList();

    // Fallback: se nenhuma lista foi encontrada, tenta nomes comuns
    if (allKeys.isEmpty) {
      final fallbackKeys = [
        "Songs",
        "Videos",
        "Albums",
        "Featured playlists",
        "Community playlists",
        "Artists"
      ];
      for (var key in fallbackKeys) {
        if (result.categories.containsKey(key) &&
            result.categories[key] is List &&
            (result.categories[key] as List).isNotEmpty) {
          allKeys.add(key);
        }
      }
    }

    railItems.value = allKeys;

    // Armazena todo o resultado (incluindo metadados)
    resultContent.value = Map<String, dynamic>.from(result.categories);

    // Cálculo da altura do rail (opcional)
    final len = railItems.where((element) => element.contains("playlists")).length;
    final calH = 30 + (railItems.length + 1 - len) * 123 + len * 150.0;
    railitemHeight.value =
        calH >= railitemHeight.value ? calH : railitemHeight.value;

    // Cria ScrollControllers para cada item
    for (String item in railItems) {
      scrollControllers[item] = ScrollController();
    }

    // Configuração para bottom nav / desktop
    if (GetPlatform.isDesktop ||
        Get.find<SettingsScreenController>().isBottomNavBarEnabled.isTrue) {
      for (var element in railItems) {
        separatedResultContent[element] = [];
      }
      tabController = TabController(length: railItems.length + 1, vsync: this);
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
    final lowerTitle = title.toLowerCase();
    if (lowerTitle.contains("song") || lowerTitle.contains("track")) {
      final songList = separatedResultContent[title].toList();
      sortSongsNVideos(songList, sortType, isAscending);
      separatedResultContent[title] = songList;
    } else if (lowerTitle.contains("playlist")) {
      final playlists = separatedResultContent[title].toList();
      sortPlayLists(playlists, sortType, isAscending);
      separatedResultContent[title] = playlists;
    } else if (lowerTitle.contains("artist") || lowerTitle.contains("channel")) {
      final artistList = separatedResultContent[title].toList();
      sortArtist(artistList, sortType, isAscending);
      separatedResultContent[title] = artistList;
    } else if (lowerTitle.contains("album")) {
      final albumList = separatedResultContent[title].toList();
      sortAlbumNSingles(albumList, sortType, isAscending);
      separatedResultContent[title] = albumList;
    }
  }

  @override
  void onClose() {
    for (String item in railItems) {
      (scrollControllers[item])!.dispose();
    }
    Get.find<HomeScreenController>().whenHomeScreenOnTop();
    tabController?.dispose();
    super.onClose();
  }
}
