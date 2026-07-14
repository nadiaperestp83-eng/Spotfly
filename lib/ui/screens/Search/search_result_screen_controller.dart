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
      
      // Carrega apenas se ainda não estiver preenchido
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
        } catch (e) {
          printERROR("Erro na aba '$tabName': $e");
        }
      }
    }
    isSeparatedResultContentFetced.value = true;
  }

  Future<void> _getInitSearchResult() async {
    isResultContentFetced.value = false;
    final args = Get.arguments;
    if (args == null) return;

    queryString.value = args;

    final result = await appProviderContainer
        .read(searchNotifierProvider.notifier)
        .search(args);

    printINFO("🔍 Chaves recebidas: ${result.categories.keys}");

    // 1. Normalização robusta: garante que todas as categorias conhecidas apareçam no menu
    Map<String, dynamic> normalizedMap = {};
    result.categories.forEach((key, value) {
      final normalizedKey = keyMapping[key] ?? key;
      if (normalizedMap.containsKey(normalizedKey) && value is List) {
        normalizedMap[normalizedKey] = [...normalizedMap[normalizedKey], ...value];
      } else {
        normalizedMap[normalizedKey] = value;
      }
    });

    // 2. Definimos as abas que queremos sempre disponíveis
    final List<String> targetKeys = [
      "Songs", "Videos", "Albums", "Artists", 
      "Featured playlists", "Community playlists"
    ];

    // 3. Adiciona ao railItems se a categoria existir na resposta ou for uma categoria padrão
    // Removemos a verificação .isNotEmpty para garantir que a aba sempre apareça
    railItems.value = targetKeys.where((key) => normalizedMap.containsKey(key)).toList();

    if (railItems.isEmpty) {
      railItems.value = normalizedMap.keys.where((key) => normalizedMap[key] is List).toList();
    }

    resultContent.value = normalizedMap;

    // Inicializa ScrollControllers e lista de conteúdo para evitar erros de renderização
    for (String item in railItems) {
      scrollControllers[item] = ScrollController();
      if (!separatedResultContent.containsKey(item)) {
        separatedResultContent[item] = normalizedMap[item] ?? [];
      }
    }

    if (GetPlatform.isDesktop || Get.find<SettingsScreenController>().isBottomNavBarEnabled.isTrue) {
      tabController = TabController(length: railItems.length + 1, vsync: this);
    }

    isResultContentFetced.value = true;
  }

  // ... (manter os métodos getContinuationContents, onSort, onClose originais)
  
  // (Nota: Certifique-se de manter o restante dos métodos que você já tinha após o _getInitSearchResult)
}
