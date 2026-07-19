import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../Search/components/desktop_search_bar.dart';
import '/ui/screens/Search/search_screen_controller.dart';
import '/ui/widgets/animated_screen_transition.dart';
import '../Library/library_combined.dart';
import '../../widgets/side_nav_bar.dart';
import '../Library/library.dart';
import '../Search/search_screen.dart';
import '../Settings/settings_screen_controller.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/create_playlist_dialog.dart';
import '../../navigator.dart';
import '../../widgets/content_list_widget.dart';
import '../../widgets/shimmer_widgets/home_shimmer.dart';
import '../../widgets/home/home_greeting_header.dart';
import '../../widgets/home/recent_played_row.dart';
import '../../widgets/home/audio_narrative_widget.dart';
import '../../widgets/home/popular_radio_stations_widget.dart';
import '../../widgets/home/recommended_for_you_widget.dart';
import '../../widgets/home/trending_songs_widget.dart';
import '../../widgets/home/recommended_list_widget.dart';
import '../../../features/player/presentation/player_widget.dart';
import 'home_screen_controller.dart';
import '../Settings/settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    final HomeScreenController homeScreenController =
        Get.find<HomeScreenController>();
    final SettingsScreenController settingsScreenController =
        Get.find<SettingsScreenController>();

    return Scaffold(
        floatingActionButton: Obx(
          () => ((homeScreenController.tabIndex.value == 0 &&
                          !GetPlatform.isDesktop) ||
                      homeScreenController.tabIndex.value == 2) &&
                  settingsScreenController.isBottomNavBarEnabled.isFalse
              ? Obx(
                  () => Padding(
                    padding: EdgeInsets.only(
                        bottom: playerController.playerPanelMinHeight.value >
                                Get.mediaQuery.padding.bottom
                            ? playerController.playerPanelMinHeight.value -
                                Get.mediaQuery.padding.bottom
                            : playerController.playerPanelMinHeight.value),
                    child: SizedBox(
                      height: 60,
                      width: 60,
                      child: FittedBox(
                        child: FloatingActionButton(
                            focusElevation: 0,
                            shape: const RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(14))),
                            elevation: 0,
                            onPressed: () async {
                              if (homeScreenController.tabIndex.value == 2) {
                                showDialog(
                                    context: context,
                                    builder: (context) =>
                                        const CreateNRenamePlaylistPopup());
                              } else {
                                Get.toNamed(ScreenNavigationSetup.searchScreen,
                                    id: ScreenNavigationSetup.id);
                              }
                              // file:///data/user/0/com.example.harmonymusic/cache/libCachedImageData/
                              //file:///data/user/0/com.example.harmonymusic/cache/just_audio_cache/
                            },
                            child: Icon(homeScreenController.tabIndex.value == 2
                                ? Icons.add
                                : Icons.search)),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        body: Obx(
          () => Row(
            children: <Widget>[
              // create a navigation rail
              settingsScreenController.isBottomNavBarEnabled.isFalse
                  ? const SideNavBar()
                  : const SizedBox(
                      width: 0,
                    ),
              //const VerticalDivider(thickness: 1, width: 2),
              Expanded(
                child: Obx(() => AnimatedScreenTransition(
                    enabled: settingsScreenController
                        .isTransitionAnimationDisabled.isFalse,
                    resverse: homeScreenController.reverseAnimationtransiton,
                    horizontalTransition:
                        settingsScreenController.isBottomNavBarEnabled.isTrue,
                    child: Center(
                      key: ValueKey<int>(homeScreenController.tabIndex.value),
                      child: const Body(),
                    ))),
              ),
            ],
          ),
        ));
  }
}

class Body extends StatelessWidget {
  const Body({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final homeScreenController = Get.find<HomeScreenController>();
    final settingsScreenController = Get.find<SettingsScreenController>();
    final size = MediaQuery.of(context).size;
    final topPadding = GetPlatform.isDesktop
        ? 85.0
        : context.isLandscape
            ? 50.0
            : size.height < 750
                ? 80.0
                : 85.0;
    // Com o NavigationRail lateral permanentemente desativado em mobile,
    // o conteÃēdo ocupa a largura total da tela; aplicamos um padding
    // horizontal simÃŠtrico (em vez do antigo "only(left: ...)") para dar
    // aquele respiro visual de app profissional em ambas as bordas.
    final horizontalPadding =
        settingsScreenController.isBottomNavBarEnabled.isTrue ? 16.0 : 5.0;
    if (homeScreenController.tabIndex.value == 0) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Stack(
          children: [
            GestureDetector(
              onTap: () {
                // for Desktop search bar
                if (GetPlatform.isDesktop) {
                  final sscontroller = Get.find<SearchScreenController>();
                  if (sscontroller.focusNode.hasFocus) {
                    sscontroller.focusNode.unfocus();
                  }
                }
              },
              child: Obx(
                () => homeScreenController.networkError.isTrue
                    ? SizedBox(
                        height: MediaQuery.of(context).size.height - 180,
                        child: Column(
                          children: [
                            Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                "home".tr,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        "networkError1".tr,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(
                                        height: 10,
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 15, vertical: 10),
                                        decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .textTheme
                                                .titleLarge!
                                                .color,
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        child: InkWell(
                                          onTap: () {
                                            homeScreenController
                                                .loadContentFromNetwork();
                                          },
                                          child: Text(
                                            "retry".tr,
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .canvasColor),
                                          ),
                                        ),
                                      ),
                                    ]),
                              ),
                            )
                          ],
                        ),
                      )
                    : Obx(() {
                        // dispose all detachached scroll controllers
                        homeScreenController.disposeDetachedScrollControllers();
                        // Antes, a Home inteira ficava escondida atrás
                        // de um shimmer genérico até isContentFetched
                        // virar true — mesmo as seções que já tinham
                        // cache local pronto (Recommended for you,
                        // Mais tocadas, narrativas, rádios) ficavam
                        // invisíveis à toa por até uns 5s, esperando
                        // só o conteúdo do YouTube Music (que É lento,
                        // depende de rede). Agora essas seções sempre
                        // aparecem na hora — só o pedaço que realmente
                        // depende do YouTube (quickPicks +
                        // middleContent + fixedContent) mostra um
                        // shimmer pequeno (HomeShimmer.compact) até
                        // isContentFetched ficar true.
                        final items = [
                          const HomeGreetingHeader(),
                          const RecentPlayedRow(),
                          Obx(() => RecommendedForYouWidget(
                              content:
                                  homeScreenController.recommendedForYou.value,
                              isLoading: homeScreenController
                                  .isRecommendedForYouLoading.value)),
                          Obx(() => TrendingSongsWidget(
                              content: homeScreenController.trendingSongs.value,
                              isLoading: homeScreenController
                                  .isTrendingSongsLoading.value)),
                          Obx(() => AudioNarrativeWidget(
                              sectionTitle: "reflectionMinutes".tr,
                              items:
                                  homeScreenController.reflectionMinutes.value,
                              isLoading: homeScreenController
                                  .isReflectionMinutesLoading.value,
                              icon: Icons.self_improvement,
                              gradientColors: const [
                                Color(0xFF4E54C8),
                                Color(0xFF8F94FB),
                              ])),
                          Obx(() => AudioNarrativeWidget(
                              sectionTitle: "nightTales".tr,
                              items: homeScreenController.nightTales.value,
                              isLoading: homeScreenController
                                  .isNightTalesLoading.value,
                              icon: Icons.auto_stories,
                              gradientColors: const [
                                Color(0xFF232526),
                                Color(0xFF414345),
                              ])),
                          Obx(() => AudioNarrativeWidget(
                              sectionTitle: "soundPoetry".tr,
                              items: homeScreenController.soundPoetry.value,
                              isLoading: homeScreenController
                                  .isSoundPoetryLoading.value,
                              icon: Icons.menu_book,
                              gradientColors: const [
                                Color(0xFFB24592),
                                Color(0xFFF15F79),
                              ])),
                          Obx(() => PopularRadioStationsWidget(
                              stations:
                                  homeScreenController.popularRadioStations.value,
                              isLoading: homeScreenController
                                  .isPopularRadioStationsLoading.value)),
                          ...homeScreenController.isContentFetched.value
                              ? [
                                  Obx(() => RecommendedListWidget(
                                      content:
                                          homeScreenController.quickPicks.value)),
                                  ...getWidgetList(
                                      homeScreenController.middleContent,
                                      homeScreenController),
                                  ...getWidgetList(
                                      homeScreenController.fixedContent,
                                      homeScreenController)
                                ]
                              : const [HomeShimmer.compact()],
                        ];
                        return ListView.builder(
                          padding:
                              EdgeInsets.only(bottom: 200, top: topPadding),
                          itemCount: items.length,
                          itemBuilder: (context, index) => items[index],
                        );
                      }),
              ),
            ),
            if (GetPlatform.isDesktop)
              Align(
                alignment: Alignment.topCenter,
                child: LayoutBuilder(builder: (context, constraints) {
                  return SizedBox(
                    width: constraints.maxWidth > 800
                        ? 800
                        : constraints.maxWidth - 40,
                    child: const Padding(
                        padding: EdgeInsets.only(top: 15.0),
                        child: DesktopSearchBar()),
                  );
                }),
              ),
            // Mini player das faixas fallback (Internet Archive/Jamendo)
            // tocadas via Riverpod — some sozinho quando não há faixa
            // tocando (ver PlayerWidget).
            Positioned(
              left: 10,
              right: 10,
              bottom: 90,
              child: const PlayerWidget(),
            ),
          ],
        ),
      );
    } else if (homeScreenController.tabIndex.value == 1) {
      return settingsScreenController.isBottomNavBarEnabled.isTrue
          ? const SearchScreen()
          : const SongsLibraryWidget();
    } else if (homeScreenController.tabIndex.value == 2) {
      return settingsScreenController.isBottomNavBarEnabled.isTrue
          ? const CombinedLibrary()
          : const PlaylistNAlbumLibraryWidget(isAlbumContent: false);
    } else if (homeScreenController.tabIndex.value == 3) {
      return settingsScreenController.isBottomNavBarEnabled.isTrue
          ? const SettingsScreen(isBottomNavActive: true)
          : const PlaylistNAlbumLibraryWidget();
    } else if (homeScreenController.tabIndex.value == 4) {
      return const LibraryArtistWidget();
    } else if (homeScreenController.tabIndex.value == 5) {
      return const SettingsScreen();
    } else {
      return Center(
        child: Text("${homeScreenController.tabIndex.value}"),
      );
    }
  }

  List<Widget> getWidgetList(
      dynamic list, HomeScreenController homeScreenController) {
    return list
        .map((content) {
          final scrollController = ScrollController();
          homeScreenController.contentScrollControllers.add(scrollController);
          return ContentListWidget(
              content: content, scrollController: scrollController);
        })
        .whereType<Widget>()
        .toList();
  }
}
