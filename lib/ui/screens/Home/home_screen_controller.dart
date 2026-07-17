import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/media_Item_builder.dart';
import '/ui/player/player_controller.dart';
import '../../../core/riverpod/app_provider_container.dart';
import '../../../features/home/state/home_notifier.dart';
import '../../../utils/update_check_flag_file.dart';
import '../../../utils/helper.dart';
import '/models/album.dart';
import '/models/playlist.dart';
import '/models/quick_picks.dart';
import '/services/music_service.dart';
import '../../../features/search/data/sources/jamendo_source.dart';
import '../Settings/settings_screen_controller.dart';
import '/ui/widgets/new_version_dialog.dart';

class HomeScreenController extends GetxController {
  final MusicServices _musicServices = Get.find<MusicServices>();
  final isContentFetched = false.obs;
  final tabIndex = 0.obs;
  final networkError = false.obs;
  final quickPicks = QuickPicks([]).obs;
  final middleContent = [].obs;
  final fixedContent = [].obs;

  /// "Recommended for you": semente = música mais recente do histórico
  /// local (Hive box "LIBRP", já mantida por PlayerController._addToRP),
  /// relacionados buscados via API (getContentRelatedToSong). Não duplica
  /// nenhuma fonte de dados nova — só combina as duas que já existem.
  final recommendedForYou = QuickPicks([]).obs;
  final isRecommendedForYouLoading = false.obs;

  /// "Estações de Rádio Popular": seção ISOLADA, não passa pelo
  /// Orquestrador (musicSourcesProvider/searchCoordinatorProvider) — o
  /// Jamendo foi removido de propósito de lá (ver comentário em
  /// providers.dart) e essa decisão continua valendo para busca/fallback
  /// normal. Aqui é uma chamada direta e exclusiva ao JamendoSource, só
  /// pra essa seção da Home, usando o client_id que já está configurado
  /// via --dart-define=JAMENDO_CLIENT_ID (ver .github/workflows).
  final popularRadioStations = <MediaItem>[].obs;
  final isPopularRadioStationsLoading = false.obs;
  final showVersionDialog = true.obs;
  //isHomeScreenOnTop var only useful if bottom nav enabled
  final isHomeSreenOnTop = true.obs;
  final List<ScrollController> contentScrollControllers = [];
  bool reverseAnimationtransiton = false;

  @override
  onInit() {
    super.onInit();
    loadContent();
    loadRecommendedForYou();
    loadPopularRadioStations();
    if (updateCheckFlag) _checkNewVersion();
  }

  /// Monta a seção "Recommended for you" a partir do histórico local:
  /// 1. Lê a Hive box "LIBRP" (sem duplicatas, mais recente por último).
  /// 2. Usa a música mais recente como "semente" pra API de relacionados.
  /// 3. Filtra fora qualquer música que já esteja no próprio histórico,
  ///    pra não recomendar o que o usuário acabou de ouvir.
  ///
  /// "Fixa" (não deve desaparecer a cada abertura do app):
  /// - Ao iniciar, primeiro mostra o que foi salvo em cache na última vez
  ///   que a busca deu certo (Hive "AppPrefs" -> "recommendedForYouCache"),
  ///   então atualiza em segundo plano.
  /// - Se a chamada de rede falhar ou vier vazia, o cache anterior é
  ///   mantido na tela (nunca sobrescreve com uma lista vazia).
  /// - Se não houver cache nenhum (primeiro uso) e a rede falhar, cai de
  ///   volta pro próprio histórico local como recomendação, pra sempre
  ///   ter algo pra mostrar quando já existe alguma música tocada.
  Future<void> loadRecommendedForYou() async {
    final appPrefs = Hive.isBoxOpen("AppPrefs")
        ? Hive.box("AppPrefs")
        : await Hive.openBox("AppPrefs");

    // 1) Mostra imediatamente o último resultado salvo, sem esperar rede.
    final cached = appPrefs.get("recommendedForYouCache") as List?;
    if (cached != null && cached.isNotEmpty) {
      try {
        final cachedItems = cached
            .map((e) => MediaItemBuilder.fromJson(Map.from(e as Map)))
            .toList();
        recommendedForYou.value =
            QuickPicks(cachedItems, title: "recommendedForYou".tr);
      } catch (_) {}
    }

    try {
      isRecommendedForYouLoading.value = true;
      final box = Hive.isBoxOpen("LIBRP")
          ? Hive.box("LIBRP")
          : await Hive.openBox("LIBRP");
      if (box.isEmpty) return; // nunca tocou nada ainda: nada a recomendar

      final historyValues = box.values
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final seedSongId = historyValues.last['videoId'] as String?;
      if (seedSongId == null) return;

      final historyIds = historyValues.map((e) => e['videoId']).toSet();
      List<Map<String, dynamic>> freshTracks = [];

      try {
        final related = await _musicServices.getContentRelatedToSong(
            seedSongId, getContentHlCode());
        freshTracks = related
            .where((track) =>
                track['videoId'] != null &&
                !historyIds.contains(track['videoId']))
            .take(10)
            .toList();
      } catch (e) {
        printERROR("getContentRelatedToSong falhou: $e");
      }

      // 2) API não trouxe nada novo (offline, erro, ou tudo já visto):
      //    cai pro próprio histórico local em vez de deixar a seção vazia.
      if (freshTracks.isEmpty) {
        if (recommendedForYou.value.songList.isNotEmpty) {
          return; // já tem cache/valor na tela, não sobrescreve com vazio
        }
        freshTracks = historyValues.reversed
            .where((track) => track['videoId'] != seedSongId)
            .take(10)
            .toList();
      }

      if (freshTracks.isEmpty) return;

      final mediaItems = freshTracks
          .map((track) => MediaItemBuilder.fromJson(track))
          .toList();

      recommendedForYou.value =
          QuickPicks(mediaItems, title: "recommendedForYou".tr);
      await appPrefs.put("recommendedForYouCache", freshTracks);
    } catch (e) {
      printERROR("Recommended for you not loaded due to: $e");
    } finally {
      isRecommendedForYouLoading.value = false;
    }
  }

  /// Busca só no Jamendo (order: popularity_month = "mais tocadas"),
  /// direto, sem passar pelo orquestrador YT->Piped->Jamendo — decisão
  /// explícita do usuário de manter essa seção isolada. Se JAMENDO_CLIENT_ID
  /// não estiver configurado no build (--dart-define), getHomeContent()
  /// já devolve lista vazia sozinho, então a seção simplesmente não aparece.
  Future<void> loadPopularRadioStations() async {
    try {
      isPopularRadioStationsLoading.value = true;
      final jamendoSource = JamendoSource(
        clientId: const String.fromEnvironment('JAMENDO_CLIENT_ID'),
      );
      final result = await jamendoSource.getHomeContent();
      if (result.isEmpty) return;
      final contents = (result.first['contents'] as List).cast<MediaItem>();
      popularRadioStations.value = contents;
    } catch (e) {
      printERROR("Popular radio stations (Jamendo) not loaded due to: $e");
    } finally {
      isPopularRadioStationsLoading.value = false;
    }
  }

  Future<void> loadContent() async {
    final box = Hive.box("AppPrefs");
    final isCachedHomeScreenDataEnabled =
        box.get("cacheHomeScreenData") ?? true;
    if (isCachedHomeScreenDataEnabled) {
      final loaded = await loadContentFromDb();

      if (loaded) {
        final currTimeSecsDiff = DateTime.now().millisecondsSinceEpoch -
            (box.get("homeScreenDataTime") ??
                DateTime.now().millisecondsSinceEpoch);
        if (currTimeSecsDiff / 1000 > 3600 * 8) {
          loadContentFromNetwork(silent: true);
        }
      } else {
        loadContentFromNetwork();
      }
    } else {
      loadContentFromNetwork();
    }
  }

  Future<bool> loadContentFromDb() async {
    final homeScreenData = await Hive.openBox("homeScreenData");
    if (homeScreenData.keys.isNotEmpty) {
      final String quickPicksType = homeScreenData.get("quickPicksType");
      final List quickPicksData = homeScreenData.get("quickPicks");
      final List middleContentData = homeScreenData.get("middleContent") ?? [];
      final List fixedContentData = homeScreenData.get("fixedContent") ?? [];
      quickPicks.value = QuickPicks(
          quickPicksData.map((e) => MediaItemBuilder.fromJson(e)).toList(),
          title: quickPicksType);
      middleContent.value = middleContentData
          .map((e) => e["type"] == "Album Content"
              ? AlbumContent.fromJson(e)
              : PlaylistContent.fromJson(e))
          .toList();
      fixedContent.value = fixedContentData
          .map((e) => e["type"] == "Album Content"
              ? AlbumContent.fromJson(e)
              : PlaylistContent.fromJson(e))
          .toList();
      isContentFetched.value = true;
      printINFO("Loaded from offline db");
      return true;
    } else {
      return false;
    }
  }

  // ========== CORREÇÃO PRINCIPAL ==========
  // Função auxiliar para extrair com segurança uma lista de MediaItem
  // a partir de uma lista que pode conter outros tipos (Playlist, Album, etc.)
  List<MediaItem> _extractMediaItems(dynamic contents) {
    if (contents == null) return [];
    final list = contents as List;
    // Filtra apenas os itens que já são MediaItem
    final mediaItems = list.whereType<MediaItem>().toList();
    // Se não houver nenhum MediaItem, tenta converter de outros tipos?
    // Por ora, retorna apenas os que já são MediaItem.
    // Você pode adicionar lógica para converter Playlist/Album se necessário.
    return mediaItems;
  }

  Future<void> loadContentFromNetwork({bool silent = false}) async {
    final box = Hive.box("AppPrefs");
    String contentType = box.get("discoverContentType") ?? "QP";

    networkError.value = false;
    try {
      List middleContentTemp = [];
      final homeContentListMap = await appProviderContainer
          .read(homeNotifierProvider.notifier)
          .fetchHomeContent(
              limit: Get.find<SettingsScreenController>()
                  .noOfHomeScreenContent
                  .value);
      if (contentType == "TR") {
        final index = homeContentListMap
            .indexWhere((element) => element['title'] == "Trending");
        if (index != -1 && index != 0) {
          // Usa a função segura
          final mediaItems = _extractMediaItems(homeContentListMap[index]["contents"]);
          if (mediaItems.isNotEmpty) {
            quickPicks.value = QuickPicks(mediaItems, title: "Trending");
          }
        } else if (index == -1) {
          List charts = await appProviderContainer
              .read(homeNotifierProvider.notifier)
              .getCharts();
          final index = charts.indexWhere((element) =>
              element['title'] ==
              (contentType == "TMV" ? "Top Music Videos" : "Trending"));
          if (index != -1) {
            final mediaItems = _extractMediaItems(charts[index]["contents"]);
            if (mediaItems.isNotEmpty) {
              quickPicks.value = QuickPicks(mediaItems, title: charts[index]['title']);
              middleContentTemp.addAll(charts);
            }
          }
        }
      } else if (contentType == "TMV") {
        final index = homeContentListMap
            .indexWhere((element) => element['title'] == "Top music videos");
        if (index != -1 && index != 0) {
          final con = homeContentListMap.removeAt(index);
          final mediaItems = _extractMediaItems(con["contents"]);
          if (mediaItems.isNotEmpty) {
            quickPicks.value = QuickPicks(mediaItems, title: con["title"]);
          }
        } else if (index == -1) {
          List charts = await appProviderContainer
              .read(homeNotifierProvider.notifier)
              .getCharts();
          final index = charts.indexWhere((element) =>
              element['title'] ==
              (contentType == "TMV" ? "Top Music Videos" : "Trending"));
          if (index != -1) {
            final mediaItems = _extractMediaItems(charts[index]["contents"]);
            if (mediaItems.isNotEmpty) {
              quickPicks.value = QuickPicks(mediaItems, title: charts[index]["title"]);
              middleContentTemp.addAll(charts);
            }
          }
        }
      } else if (contentType == "BOLI") {
        try {
          final songId = box.get("recentSongId");
          if (songId != null) {
            final rel = (await _musicServices.getContentRelatedToSong(
                songId, getContentHlCode()));
            final con = rel.removeAt(0);
            final mediaItems = _extractMediaItems(con["contents"]);
            if (mediaItems.isNotEmpty) {
              quickPicks.value = QuickPicks(mediaItems);
            }
            middleContentTemp.addAll(rel);
          }
        } catch (e) {
          printERROR(
              "Seems Based on last interaction content currently not available!");
        }
      }

      if (quickPicks.value.songList.isEmpty) {
        final index = homeContentListMap
            .indexWhere((element) => element['title'] == "Quick picks");
        if (index != -1) {
          final con = homeContentListMap.removeAt(index);
          final mediaItems = _extractMediaItems(con["contents"]);
          if (mediaItems.isNotEmpty) {
            quickPicks.value = QuickPicks(mediaItems, title: "Quick picks");
          }
        } else if (homeContentListMap.isNotEmpty) {
          final con = homeContentListMap.removeAt(0);
          final mediaItems = _extractMediaItems(con["contents"]);
          if (mediaItems.isNotEmpty) {
            quickPicks.value = QuickPicks(mediaItems, title: con["title"] ?? "Quick picks");
          }
        }
      }

      middleContent.value = _setContentList(middleContentTemp);
      fixedContent.value = _setContentList(homeContentListMap);

      isContentFetched.value = true;

      cachedHomeScreenData(updateAll: true);
      await Hive.box("AppPrefs")
          .put("homeScreenDataTime", DateTime.now().millisecondsSinceEpoch);
    } catch (e, st) {
      printERROR("Home Content not loaded due to: $e");
      printERROR(st.toString());
      await Future.delayed(const Duration(seconds: 1));
      networkError.value = !silent;
      if (!silent) {
        Get.snackbar(
          'Erro ao carregar a Home',
          e.toString(),
          duration: const Duration(seconds: 10),
          isDismissible: true,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
  }

  List _setContentList(
    List<dynamic> contents,
  ) {
    List contentTemp = [];
    for (var content in contents) {
      if((content["contents"]).isEmpty) continue;
      if ((content["contents"][0]).runtimeType == Playlist) {
        final tmp = PlaylistContent(
            playlistList: (content["contents"]).whereType<Playlist>().toList(),
            title: content["title"]);
        if (tmp.playlistList.length >= 2) {
          contentTemp.add(tmp);
        }
      } else if ((content["contents"][0]).runtimeType == Album) {
        final tmp = AlbumContent(
            albumList: (content["contents"]).whereType<Album>().toList(),
            title: content["title"]);
        if (tmp.albumList.length >= 2) {
          contentTemp.add(tmp);
        }
      }
    }
    return contentTemp;
  }

  // ========== CORREÇÃO NO changeDiscoverContent ==========
  Future<void> changeDiscoverContent(dynamic val, {String? songId}) async {
    QuickPicks? quickPicks_;
    if (val == 'QP') {
      final homeContentListMap = await _musicServices.getHome(limit: 3);
      final mediaItems = _extractMediaItems(homeContentListMap[0]["contents"]);
      if (mediaItems.isNotEmpty) {
        quickPicks_ = QuickPicks(mediaItems, title: homeContentListMap[0]["title"]);
      }
    } else if (val == "TMV" || val == 'TR') {
      try {
        final charts =
            await appProviderContainer.read(homeNotifierProvider.notifier).getCharts();
        final index = charts.indexWhere((element) =>
            element['title'] ==
            (val == "TMV" ? "Top Music Videos" : "Trending"));
        if (index != -1) {
          final mediaItems = _extractMediaItems(charts[index]["contents"]);
          if (mediaItems.isNotEmpty) {
            quickPicks_ = QuickPicks(mediaItems, title: charts[index]["title"]);
          }
        }
      } catch (e) {
        printERROR(
            "Seems ${val == "TMV" ? "Top music videos" : "Trending songs"} currently not available!");
      }
    } else {
      songId ??= Hive.box("AppPrefs").get("recentSongId");
      if (songId != null) {
        try {
          final value = await _musicServices.getContentRelatedToSong(
              songId, getContentHlCode());
          middleContent.value = _setContentList(value);
          if (value.isNotEmpty && (value[0]['title']).contains("like")) {
            final mediaItems = _extractMediaItems(value[0]["contents"]);
            if (mediaItems.isNotEmpty) {
              quickPicks_ = QuickPicks(mediaItems);
            }
            Hive.box("AppPrefs").put("recentSongId", songId);
          }
          // ignore: empty_catches
        } catch (e) {}
      }
    }
    if (quickPicks_ == null) return;

    quickPicks.value = quickPicks_;

    cachedHomeScreenData(updateQuickPicksNMiddleContent: true);
    await Hive.box("AppPrefs")
        .put("homeScreenDataTime", DateTime.now().millisecondsSinceEpoch);
  }

  String getContentHlCode() {
    const List<String> unsupportedLangIds = ["ia", "ga", "fj", "eo"];
    final userLangId =
        Get.find<SettingsScreenController>().currentAppLanguageCode.value;
    return unsupportedLangIds.contains(userLangId) ? "en" : userLangId;
  }

  void onSideBarTabSelected(int index) {
    reverseAnimationtransiton = index > tabIndex.value;
    tabIndex.value = index;
  }

  void onBottonBarTabSelected(int index) {
    reverseAnimationtransiton = index > tabIndex.value;
    tabIndex.value = index;
  }

  void _checkNewVersion() {
    showVersionDialog.value =
        Hive.box("AppPrefs").get("newVersionVisibility") ?? true;
    if (showVersionDialog.isTrue) {
      newVersionCheck(Get.find<SettingsScreenController>().currentVersion)
          .then((value) {
        if (value) {
          showDialog(
              context: Get.context!,
              builder: (context) => const NewVersionDialog());
        }
      });
    }
  }

  void onChangeVersionVisibility(bool val) {
    Hive.box("AppPrefs").put("newVersionVisibility", !val);
    showVersionDialog.value = !val;
  }

  ///This is used to minimized bottom navigation bar by setting [isHomeSreenOnTop.value] to `true` and set mini player height.
  ///
  ///and applicable/useful if bottom nav enabled
  void whenHomeScreenOnTop() {
    if (Get.find<SettingsScreenController>().isBottomNavBarEnabled.isTrue) {
      final currentRoute = getCurrentRouteName();
      final isHomeOnTop = currentRoute == '/homeScreen';
      final isResultScreenOnTop = currentRoute == '/searchResultScreen';
      final playerCon = Get.find<PlayerController>();

      isHomeSreenOnTop.value = isHomeOnTop;

      // Set miniplayer height accordingly
      if (!playerCon.initFlagForPlayer) {
        if (isHomeOnTop) {
          playerCon.playerPanelMinHeight.value = 75.0;
        } else {
          Future.delayed(
              isResultScreenOnTop
                  ? const Duration(milliseconds: 300)
                  : Duration.zero, () {
            playerCon.playerPanelMinHeight.value =
                75.0 + Get.mediaQuery.viewPadding.bottom;
          });
        }
      }
    }
  }

  Future<void> cachedHomeScreenData({
    bool updateAll = false,
    bool updateQuickPicksNMiddleContent = false,
  }) async {
    if (Get.find<SettingsScreenController>().cacheHomeScreenData.isFalse ||
        quickPicks.value.songList.isEmpty) {
      return;
    }

    final homeScreenData = Hive.box("homeScreenData");

    if (updateQuickPicksNMiddleContent) {
      await homeScreenData.putAll({
        "quickPicksType": quickPicks.value.title,
        "quickPicks": _getContentDataInJson(quickPicks.value.songList,
            isQuickPicks: true),
        "middleContent": _getContentDataInJson(middleContent.toList()),
      });
    } else if (updateAll) {
      await homeScreenData.putAll({
        "quickPicksType": quickPicks.value.title,
        "quickPicks": _getContentDataInJson(quickPicks.value.songList,
            isQuickPicks: true),
        "middleContent": _getContentDataInJson(middleContent.toList()),
        "fixedContent": _getContentDataInJson(fixedContent.toList())
      });
    }

    printINFO("Saved Homescreen data data");
  }

  List<Map<String, dynamic>> _getContentDataInJson(List content,
      {bool isQuickPicks = false}) {
    if (isQuickPicks) {
      return content.toList().map((e) => MediaItemBuilder.toJson(e)).toList();
    } else {
      return content.map((e) {
        if (e.runtimeType == AlbumContent) {
          return (e as AlbumContent).toJson();
        } else {
          return (e as PlaylistContent).toJson();
        }
      }).toList();
    }
  }

  void disposeDetachedScrollControllers({bool disposeAll = false}) {
    final scrollControllersCopy = contentScrollControllers.toList();
    for (final contoller in scrollControllersCopy) {
      if (!contoller.hasClients || disposeAll) {
        contentScrollControllers.remove(contoller);
        contoller.dispose();
      }
    }
  }

  @override
  void dispose() {
    disposeDetachedScrollControllers(disposeAll: true);
    super.dispose();
  }
}
