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

    if (value > 0 &&
        (!separatedResultContent.containsKey(railItems[value - 1]) ||
            separatedResultContent[railItems[value - 1]].isEmpty)) {
      final tabName = railItems[value - 1];
      final itemCount = (tabName == 'Songs' || tabName == 'Videos') ? 25 : 10;
      final filterParams =
          (resultContent['searchEndpoint'] as Map?)?[tabName] as String?;

      try {
        if (filterParams == null) {
          // Fonte de fallback (Piped/Jamendo): não tem abas/paginação reais.
          // Reaproveita o que já veio na busca inicial.
          separatedResultContent[tabName] =
              List.from(resultContent[tabName] ?? []);
          additionalParamNext[tabName] = {};
        } else {
          // Antes: sem try/catch aqui. Se o Orquestrador (SearchCoordinator)
          // falhasse pra essa aba (ex: todas as fontes indisponíveis), a
          // exceção subia sem tratamento, `isSeparatedResultContentFetced`
          // nunca virava true, e a aba ficava girando pra sempre — esse
          // era o "busca refinada não funciona".
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
          (scrollController)!.addListener(() {
            double maxScroll = scrollController.position.maxScrollExtent;
            double currentScroll = scrollController.position.pixels;
            if (currentScroll >= maxScroll / 2 &&
                additionalParamNext[tabName]['additionalParams'] !=
                    '&ctoken=null&continuation=null') {
              if (!continuationInProgress) {
                printINFO("Acchhsk");
                continuationInProgress = true;
                getContinuationContents();
              }
            }
          });
        }
      } catch (e, st) {
        // Nunca deixa a aba presa em loading: sempre marca como resolvida
        // e mostra o erro real na tela pra diagnóstico direto no celular.
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
      // Antes: sem try/catch. Um erro aqui deixava continuationInProgress
      // travado em true, bloqueando qualquer novo carregamento por scroll
      // até o usuário sair e voltar pra tela.
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
    if (args != null) {
      queryString.value = args;

      final result = await appProviderContainer
          .read(searchNotifierProvider.notifier)
          .search(args);

      // Diagnóstico: SearchNotifier.search() usa AsyncValue.guard, então
      // mesmo se TODAS as fontes falharem ele nunca lança exceção aqui —
      // só devolve um SearchResult vazio, indistinguível de "sem
      // resultados pra essa busca". Checando o estado bruto do provider
      // conseguimos saber se foi erro de verdade e mostrar na tela.
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

      resultContent.value = Map<String, dynamic>.from(result.categories);

      final allKeys = resultContent.keys.where((element) => ([
            "Songs",
            "Videos",
            "Albums",
            "Featured playlists",
            "Community playlists",
            "Artists"
          ]).contains(element));
      railItems.value = List<String>.from(allKeys);
      final len =
          railItems.where((element) => element.contains("playlists")).length;
      final calH = 30 + (railItems.length + 1 - len) * 123 + len * 150.0;
      railitemHeight.value =
          calH >= railitemHeight.value ? calH : railitemHeight.value;

      //ScrollControlers for list Continuation callback implementarion
      for (String item in railItems) {
        scrollControllers[item] = ScrollController();
      }

      //Case if bottom nav used
      if (GetPlatform.isDesktop ||
          Get.find<SettingsScreenController>().isBottomNavBarEnabled.isTrue) {
        // assiging init val
        for (var element in railItems) {
          separatedResultContent[element] = [];
        }

        //tab controller for v2
        tabController =
            TabController(length: railItems.length + 1, vsync: this);

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
  }

  void onSort(SortType sortType, bool isAscending, String title) {
    if (title == "Songs" || title == "Videos") {
      final songList = separatedResultContent[title].toList();
      sortSongsNVideos(songList, sortType, isAscending);
      separatedResultContent[title] = songList;
    } else if (title.contains('playlists')) {
      final playlists = separatedResultContent[title].toList();
      sortPlayLists(playlists, sortType, isAscending);
      separatedResultContent[title] = playlists;
    } else if (title == "Artists") {
      final artistList = separatedResultContent[title].toList();
      sortArtist(artistList, sortType, isAscending);
      separatedResultContent[title] = artistList;
    } else if (title == "Albums") {
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
