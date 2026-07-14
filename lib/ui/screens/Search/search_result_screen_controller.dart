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

  static const Map<String, String> keyMapping = {
    'Tracks': 'Songs',
    'Songs': 'Songs',
    'Videos': 'Videos',
    'Albums': 'Albums',
    'Artists': 'Artists',
    'Channels': 'Artists',
    'Featured playlists': 'Featured playlists',
    'Community playlists': 'Community playlists',
    'Playlists': 'Featured playlists',
  };

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

    final result = await appProviderContainer.read(searchNotifierProvider.notifier).search(args);

    // Normalização sem descartar chaves vazias
    Map<String, dynamic> normalizedMap = {};
    result.categories.forEach((key, value) {
      final normalizedKey = keyMapping[key] ?? key;
      if (normalizedMap.containsKey(normalizedKey) && value is List) {
        normalizedMap[normalizedKey] = [...normalizedMap[normalizedKey], ...value];
      } else {
        normalizedMap[normalizedKey] = value;
      }
    });

    // Lista de categorias esperadas
    final List<String> targetKeys = ["Songs", "Videos", "Albums", "Artists", "Featured playlists", "Community playlists"];
    
    // Adiciona as chaves que existem no resultado
    railItems.value = targetKeys.where((key) => normalizedMap.containsKey(key)).toList();

    // Se nenhuma das chaves esperadas foi encontrada, adiciona o que vier de listas
    if (railItems.isEmpty) {
      railItems.value = normalizedMap.keys.where((key) => normalizedMap[key] is List).toList();
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
