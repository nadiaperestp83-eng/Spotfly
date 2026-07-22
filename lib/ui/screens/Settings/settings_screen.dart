import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/utils/helper.dart';
import 'package:harmonymusic/utils/lang_mapping.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/common_dialog_widget.dart';
import '../../widgets/cust_switch.dart';
import '../../widgets/export_file_dialog.dart';
import '../../widgets/backup_dialog.dart';
import '../../widgets/restore_dialog.dart';
import '../Library/library_controller.dart';
import '../../widgets/snackbar.dart';
import '/ui/widgets/link_piped.dart';
import '/services/music_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/utils/theme_controller.dart';
import 'package:google_fonts/google_fonts.dart';

import 'components/custom_expansion_tile.dart';
import 'components/ios_grouped_section.dart';
import 'settings_screen_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsScreenController>();
    final topPadding = context.isLandscape ? 50.0 : 90.0;
    final isDesktop = GetPlatform.isDesktop;
    return Container(
      // Fundo da tela: iOS claro (kAppleGroupedBackground) no ThemeType.light,
      // e o fundo profundo do tema no Dark/Dynamic — antes ficava sempre
      // fixo em claro, mesmo com o Dark selecionado.
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: isBottomNavActive
            ? EdgeInsets.only(left: 20, top: topPadding, right: 15)
            : EdgeInsets.only(top: topPadding, left: 16, right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "settings".tr,
                  style: GoogleFonts.inter(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.titleMedium?.color,
                  ),
                ),
              ),
            ),
            Expanded(
                child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 200, top: 4),
              children: [
              Obx(
                () => settingsController.isNewVersionAvailable.value
                    ? Padding(
                        padding: const EdgeInsets.only(
                            top: 8.0, right: 10, bottom: 8.0),
                        child: Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                            onTap: () {
                              launchUrl(
                                Uri.parse(
                                  'https://github.com/anandnet/Harmony-Music/releases/latest',
                                ),
                                mode: LaunchMode.externalApplication,
                              );
                            },
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            tileColor: Theme.of(context).colorScheme.secondary,
                            contentPadding:
                                const EdgeInsets.only(left: 8, right: 10),
                            leading:
                                const CircleAvatar(child: Icon(Icons.download)),
                            title: Text("newVersionAvailable".tr),
                            visualDensity: const VisualDensity(horizontal: -2),
                            subtitle: Text(
                              "goToDownloadPage".tr,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium!
                                  .copyWith(
                                      color: Colors.white70, fontSize: 13),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              IosGroupedSection(
                children: [
              CustomExpansionTile(
                accentColor: kiTunesAccentColors[0],
                title: "personalisation".tr,
                icon: Icons.palette,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 5, right: 10),
                    title: Text("themeMode".tr),
                    subtitle: Obx(
                      () => Text(
                          settingsController.themeModetype.value ==
                                  ThemeType.dynamic
                              ? "dynamic".tr
                              : settingsController.themeModetype.value ==
                                      ThemeType.system
                                  ? "systemDefault".tr
                                  : settingsController.themeModetype.value ==
                                          ThemeType.dark
                                      ? "dark".tr
                                      : "light".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                    onTap: () => showDialog(
                      context: context,
                      builder: (context) => const ThemeSelectorDialog(),
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 5, right: 10),
                    title: Text("language".tr),
                    subtitle: Text("languageDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium),
                    trailing: Obx(
                      () => DropdownButton(
                        menuMaxHeight: Get.height - 250,
                        dropdownColor: Theme.of(context).cardColor,
                        underline: const SizedBox.shrink(),
                        style: Theme.of(context).textTheme.titleSmall,
                        value: settingsController.currentAppLanguageCode.value,
                        items: langMap.entries
                            .map((lang) => DropdownMenuItem(
                                  value: lang.key,
                                  child: Text(lang.value),
                                ))
                            .whereType<DropdownMenuItem<String>>()
                            .toList(),
                        selectedItemBuilder: (context) =>
                            langMap.entries.map<Widget>((item) {
                          return Container(
                            alignment: Alignment.centerRight,
                            constraints: const BoxConstraints(minWidth: 50),
                            child: Text(
                              item.value,
                            ),
                          );
                        }).toList(),
                        onChanged: settingsController.setAppLanguage,
                      ),
                    ),
                  ),
                  if (!isDesktop)
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("playerUi".tr),
                      subtitle: Text("playerUiDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      trailing: Obx(
                        () => DropdownButton(
                          dropdownColor: Theme.of(context).cardColor,
                          underline: const SizedBox.shrink(),
                          value: settingsController.playerUi.value,
                          items: [
                            DropdownMenuItem(
                                value: 0, child: Text("standard".tr)),
                            DropdownMenuItem(
                              value: 1,
                              child: Text("gesture".tr),
                            ),
                          ],
                          onChanged: settingsController.setPlayerUi,
                        ),
                      ),
                    ),
                  if (!isDesktop)
                    ListTile(
                        contentPadding:
                            const EdgeInsets.only(left: 5, right: 10),
                        title: Text("enableBottomNav".tr),
                        subtitle: Text("enableBottomNavDes".tr,
                            style: Theme.of(context).textTheme.bodyMedium),
                        trailing: Obx(
                          () => CustSwitch(
                              value: settingsController
                                  .isBottomNavBarEnabled.isTrue,
                              onChanged: settingsController.enableBottomNavBar),
                        )),
                  ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("disableTransitionAnimation".tr),
                      subtitle: Text("disableTransitionAnimationDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      trailing: Obx(
                        () => CustSwitch(
                            value: settingsController
                                .isTransitionAnimationDisabled.isTrue,
                            onChanged:
                                settingsController.disableTransitionAnimation),
                      )),
                  ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("enableSlidableAction".tr),
                      subtitle: Text("enableSlidableActionDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      trailing: Obx(
                        () => CustSwitch(
                            value:
                                settingsController.slidableActionEnabled.isTrue,
                            onChanged: settingsController.toggleSlidableAction),
                      )),
                ],
              ),
              CustomExpansionTile(
                  accentColor: kiTunesAccentColors[1],
                  title: "content".tr,
                  icon: Icons.music_video,
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("setDiscoverContent".tr),
                      subtitle: Obx(() => Text(
                          settingsController.discoverContentType.value == "QP"
                              ? "quickpicks".tr
                              : settingsController.discoverContentType.value ==
                                      "TMV"
                                  ? "topmusicvideos".tr
                                  : settingsController
                                              .discoverContentType.value ==
                                          "TR"
                                      ? "trending".tr
                                      : "basedOnLast".tr,
                          style: Theme.of(context).textTheme.bodyMedium)),
                      onTap: () => showDialog(
                        context: context,
                        builder: (context) =>
                            const DiscoverContentSelectorDialog(),
                      ),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("homeContentCount".tr),
                      subtitle: Text("homeContentCountDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      trailing: Obx(
                        () => DropdownButton(
                          dropdownColor: Theme.of(context).cardColor,
                          underline: const SizedBox.shrink(),
                          value: settingsController.noOfHomeScreenContent.value,
                          items: ([3, 5, 7, 9, 11])
                              .map((e) =>
                                  DropdownMenuItem(value: e, child: Text("$e")))
                              .toList(),
                          onChanged: settingsController.setContentNumber,
                        ),
                      ),
                    ),
                    ListTile(
                        contentPadding:
                            const EdgeInsets.only(left: 5, right: 10),
                        title: Text("cacheHomeScreenData".tr),
                        subtitle: Text("cacheHomeScreenDataDes".tr,
                            style: Theme.of(context).textTheme.bodyMedium),
                        trailing: Obx(
                          () => CustSwitch(
                              value:
                                  settingsController.cacheHomeScreenData.value,
                              onChanged:
                                  settingsController.toggleCacheHomeScreenData),
                        )),
                    ListTile(
                      contentPadding:
                          const EdgeInsets.only(left: 5, right: 10, top: 0),
                      title: Text("Piped".tr),
                      subtitle: Text("linkPipedDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      trailing: TextButton(
                          child: Obx(() => Text(
                                settingsController.isLinkedWithPiped.value
                                    ? "unLink".tr
                                    : "link".tr,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium!
                                    .copyWith(fontSize: 15),
                              )),
                          onPressed: () {
                            if (settingsController.isLinkedWithPiped.isFalse) {
                              showDialog(
                                context: context,
                                builder: (context) => const LinkPiped(),
                              ).whenComplete(
                                  () => Get.delete<PipedLinkedController>());
                            } else {
                              settingsController.unlinkPiped();
                            }
                          }),
                    ),
                    Obx(() => (settingsController.isLinkedWithPiped.isTrue)
                        ? ListTile(
                            contentPadding: const EdgeInsets.only(
                                left: 5, right: 10, top: 0),
                            title: Text("resetblacklistedplaylist".tr),
                            subtitle: Text("resetblacklistedplaylistDes".tr,
                                style: Theme.of(context).textTheme.bodyMedium),
                            trailing: TextButton(
                                child: Text(
                                  "reset".tr,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium!
                                      .copyWith(fontSize: 15),
                                ),
                                onPressed: () async {
                                  await Get.find<LibraryPlaylistsController>()
                                      .resetBlacklistedPlaylist();
                                  ScaffoldMessenger.of(Get.context!)
                                      .showSnackBar(snackbar(Get.context!,
                                          "blacklistPlstResetAlert".tr,
                                          size: SanckBarSize.MEDIUM));
                                }),
                          )
                        : const SizedBox.shrink()),
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("clearImgCache".tr),
                      subtitle: Text(
                        "clearImgCacheDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      isThreeLine: true,
                      onTap: () {
                        settingsController.clearImagesCache().then((value) =>
                            ScaffoldMessenger.of(Get.context!).showSnackBar(
                                snackbar(Get.context!, "clearImgCacheAlert".tr,
                                    size: SanckBarSize.BIG)));
                      },
                    ),
                  ]),
              CustomExpansionTile(
                accentColor: kiTunesAccentColors[2],
                title: "music&Playback".tr,
                icon: Icons.music_note,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 5, right: 10),
                    title: Text("streamingQuality".tr),
                    subtitle: Text("streamingQualityDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium),
                    trailing: Obx(
                      () => DropdownButton(
                        dropdownColor: Theme.of(context).cardColor,
                        underline: const SizedBox.shrink(),
                        value: settingsController.streamingQuality.value,
                        items: [
                          DropdownMenuItem(
                              value: AudioQuality.Low, child: Text("low".tr)),
                          DropdownMenuItem(
                            value: AudioQuality.High,
                            child: Text("high".tr),
                          ),
                        ],
                        onChanged: settingsController.setStreamingQuality,
                      ),
                    ),
                  ),
                  if (GetPlatform.isAndroid)
                    ListTile(
                        contentPadding:
                            const EdgeInsets.only(left: 5, right: 10),
                        title: Text("loudnessNormalization".tr),
                        subtitle: Text("loudnessNormalizationDes".tr,
                            style: Theme.of(context).textTheme.bodyMedium),
                        trailing: Obx(
                          () => CustSwitch(
                              value: settingsController
                                  .loudnessNormalizationEnabled.value,
                              onChanged: settingsController
                                  .toggleLoudnessNormalization),
                        )),
                  if (!isDesktop)
                    ListTile(
                        contentPadding:
                            const EdgeInsets.only(left: 5, right: 10),
                        title: Text("cacheSongs".tr),
                        subtitle: Text("cacheSongsDes".tr,
                            style: Theme.of(context).textTheme.bodyMedium),
                        trailing: Obx(
                          () => CustSwitch(
                              value: settingsController.cacheSongs.value,
                              onChanged:
                                  settingsController.toggleCachingSongsValue),
                        )),
                  if (!isDesktop)
                    ListTile(
                        contentPadding:
                            const EdgeInsets.only(left: 5, right: 10),
                        title: Text("skipSilence".tr),
                        subtitle: Text("skipSilenceDes".tr,
                            style: Theme.of(context).textTheme.bodyMedium),
                        trailing: Obx(
                          () => CustSwitch(
                              value:
                                  settingsController.skipSilenceEnabled.value,
                              onChanged: settingsController.toggleSkipSilence),
                        )),
                  if (isDesktop)
                    ListTile(
                        contentPadding:
                            const EdgeInsets.only(left: 5, right: 10),
                        title: Text("backgroundPlay".tr),
                        subtitle: Text("backgroundPlayDes".tr,
                            style: Theme.of(context).textTheme.bodyMedium),
                        trailing: Obx(
                          () => CustSwitch(
                              value: settingsController
                                  .backgroundPlayEnabled.value,
                              onChanged:
                                  settingsController.toggleBackgroundPlay),
                        )),
                  ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("keepScreenOnWhilePlaying".tr),
                      subtitle: Text("keepScreenOnWhilePlayingDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      trailing: Obx(
                        () => CustSwitch(
                            value: settingsController.keepScreenAwake.value,
                            onChanged:
                                settingsController.toggleKeepScreenAwake),
                      )),
                  ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("restoreLastPlaybackSession".tr),
                      subtitle: Text("restoreLastPlaybackSessionDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      trailing: Obx(
                        () => CustSwitch(
                            value:
                                settingsController.restorePlaybackSession.value,
                            onChanged: settingsController
                                .toggleRestorePlaybackSession),
                      )),
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 5, right: 10),
                    title: Text("autoOpenPlayer".tr),
                    subtitle: Text("autoOpenPlayerDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium),
                    trailing: Obx(
                      () => CustSwitch(
                          value: settingsController.autoOpenPlayer.value,
                          onChanged: settingsController.toggleAutoOpenPlayer),
                    ),
                  ),
                  if (!isDesktop)
                    ListTile(
                      contentPadding:
                          const EdgeInsets.only(left: 5, right: 10, top: 0),
                      title: Text("equalizer".tr),
                      subtitle: Text("equalizerDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      onTap: () async {
                        try {
                          await Get.find<PlayerController>().openEqualizer();
                        } catch (e) {
                          printERROR(e);
                        }
                      },
                    ),
                  if (!isDesktop)
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("stopMusicOnTaskClear".tr),
                      subtitle: Text("stopMusicOnTaskClearDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      trailing: Obx(
                        () => CustSwitch(
                            value: settingsController
                                .stopPlyabackOnSwipeAway.value,
                            onChanged: settingsController
                                .toggleStopPlyabackOnSwipeAway),
                      ),
                    ),
                  GetPlatform.isAndroid
                      ? Obx(
                          () => ListTile(
                            contentPadding:
                                const EdgeInsets.only(left: 5, right: 10),
                            title: Text("ignoreBatOpt".tr),
                            onTap: settingsController
                                    .isIgnoringBatteryOptimizations.isFalse
                                ? settingsController
                                    .enableIgnoringBatteryOptimizations
                                : null,
                            subtitle: Obx(() => RichText(
                                  text: TextSpan(
                                    text:
                                        "${"status".tr}: ${settingsController.isIgnoringBatteryOptimizations.isTrue ? "enabled".tr : "disabled".tr}\n",
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium!
                                        .copyWith(fontWeight: FontWeight.bold),
                                    children: <TextSpan>[
                                      TextSpan(
                                          text: "ignoreBatOptDes".tr,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium),
                                    ],
                                  ),
                                )),
                          ),
                        )
                      : const SizedBox.shrink(),
                ],
              ),
              ]),
              const SizedBox(height: 20),
              IosGroupedSection(
                children: [
              CustomExpansionTile(
                accentColor: kiTunesAccentColors[3],
                title: "download".tr,
                icon: Icons.download,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 5, right: 10),
                    title: Text("autoDownFavSong".tr),
                    subtitle: Text("autoDownFavSongDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium),
                    trailing: Obx(
                      () => CustSwitch(
                          value: settingsController
                              .autoDownloadFavoriteSongEnabled.value,
                          onChanged: settingsController
                              .toggleAutoDownloadFavoriteSong),
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 5, right: 10),
                    title: Text("downloadingFormat".tr),
                    subtitle: Text("downloadingFormatDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium),
                    trailing: Obx(
                      () => DropdownButton(
                        dropdownColor: Theme.of(context).cardColor,
                        underline: const SizedBox.shrink(),
                        value: settingsController.downloadingFormat.value,
                        items: const [
                          DropdownMenuItem(
                              value: "opus", child: Text("Opus/Ogg")),
                          DropdownMenuItem(
                            value: "m4a",
                            child: Text("M4a"),
                          ),
                        ],
                        onChanged: settingsController.changeDownloadingFormat,
                      ),
                    ),
                  ),
                  ListTile(
                    trailing: TextButton(
                      child: Text(
                        "reset".tr,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium!
                            .copyWith(fontSize: 15),
                      ),
                      onPressed: () {
                        settingsController.resetDownloadLocation();
                      },
                    ),
                    contentPadding:
                        const EdgeInsets.only(left: 5, right: 10, top: 0),
                    title: Text("downloadLocation".tr),
                    subtitle: Obx(() => Text(
                        settingsController.isCurrentPathsupportDownDir
                            ? "In App storage directory"
                            : settingsController.downloadLocationPath.value,
                        style: Theme.of(context).textTheme.bodyMedium)),
                    onTap: () async {
                      settingsController.setDownloadLocation();
                    },
                  ),
                  if (GetPlatform.isAndroid)
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("exportDowloadedFiles".tr),
                      subtitle: Text(
                        "exportDowloadedFilesDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      isThreeLine: true,
                      onTap: () => showDialog(
                        context: context,
                        builder: (context) => const ExportFileDialog(),
                      ).whenComplete(
                          () => Get.delete<ExportFileDialogController>()),
                    ),
                  if (GetPlatform.isAndroid)
                    ListTile(
                      contentPadding:
                          const EdgeInsets.only(left: 5, right: 10, top: 0),
                      title: Text("exportedFileLocation".tr),
                      subtitle: Obx(() => Text(
                          settingsController.exportLocationPath.value,
                          style: Theme.of(context).textTheme.bodyMedium)),
                      onTap: () async {
                        settingsController.setExportedLocation();
                      },
                    ),
                ],
              ),
              CustomExpansionTile(
                  accentColor: kiTunesAccentColors[4],
                  title: "${"backup".tr} & ${"restore".tr}",
                  icon: Icons.restore,
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("backupAppData".tr),
                      subtitle: Text(
                        "backupSettingsAndPlaylistsDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      isThreeLine: true,
                      onTap: () => showDialog(
                        context: context,
                        builder: (context) => const BackupDialog(),
                      ).whenComplete(
                          () => Get.delete<BackupDialogController>()),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("restoreAppData".tr),
                      subtitle: Text(
                        "restoreSettingsAndPlaylistsDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      isThreeLine: true,
                      onTap: () => showDialog(
                        context: context,
                        builder: (context) => const RestoreDialog(),
                      ).whenComplete(
                          () => Get.delete<RestoreDialogController>()),
                    ),
                  ]),
              ]),
              const SizedBox(height: 20),
              IosGroupedSection(
                children: [
              CustomExpansionTile(
                accentColor: kiTunesAccentColors[5],
                  icon: Icons.miscellaneous_services,
                  title: "misc".tr,
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("resetToDefault".tr),
                      subtitle: Text(
                        "resetToDefaultDes".tr,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      onTap: () {
                        settingsController
                            .resetAppSettingsToDefault()
                            .then((_) {
                          ScaffoldMessenger.of(Get.context!).showSnackBar(
                              snackbar(Get.context!, "resetToDefaultMsg".tr,
                                  size: SanckBarSize.BIG,
                                  duration: const Duration(seconds: 2)));
                        });
                      },
                    ),
                  ]),
              CustomExpansionTile(
                accentColor: kiTunesAccentColors[6],
                  icon: Icons.vpn_lock,
                  title: "proxy".tr,
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("enableProxy".tr),
                      subtitle: Text("enableProxyDes".tr,
                          style: Theme.of(context).textTheme.bodyMedium),
                      trailing: Obx(
                        () => CustSwitch(
                          value: settingsController.proxyEnabled.isTrue,
                          onChanged: settingsController.toggleProxy,
                        ),
                      ),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 5, right: 10),
                      title: Text("proxyAddress".tr),
                      subtitle: Obx(
                        () => Text(
                          settingsController.proxyAddress.value.isEmpty
                              ? "proxyAddressDes".tr
                              : settingsController.proxyAddress.value,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      onTap: () => showDialog(
                        context: context,
                        builder: (context) => const ProxyAddressDialog(),
                      ),
                    ),
                  ]),
              ]),
              const SizedBox(height: 20),
              IosGroupedSection(
                children: [
              CustomExpansionTile(
                accentColor: kiTunesAccentColors[7],
                icon: Icons.info,
                title: "appInfo".tr,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 5, right: 10),
                    title: Text("github".tr),
                    subtitle: Text(
                      "${"githubDes".tr}${((Get.find<PlayerController>().playerPanelMinHeight.value) == 0 || !isBottomNavActive) ? "" : "\n\n${settingsController.currentVersion} ${"by".tr} anandnet"}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    isThreeLine: true,
                    onTap: () {
                      launchUrl(
                        Uri.parse(
                          'https://github.com/anandnet/Harmony-Music',
                        ),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                  ),
                  const Divider(),
                  SizedBox(
                    child: Column(
                      children: [
                        Text(
                          "Spotifly",
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(settingsController.currentVersion,
                            style: Theme.of(context).textTheme.titleMedium)
                      ],
                    ),
                  ),
                ],
              )
              ]),
            ],
          )),
          Padding(
            padding: const EdgeInsets.only(bottom: 20.0),
            child: Text(
              "${settingsController.currentVersion} ${"by".tr} anandnet",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class ThemeSelectorDialog extends StatelessWidget {
  const ThemeSelectorDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsScreenController>();
    return CommonDialog(
      child: Container(
        height: 300,
        //color: Theme.of(context).cardColor,
        padding: const EdgeInsets.only(top: 30, left: 5, right: 30, bottom: 10),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.only(left: 20.0, bottom: 5),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "themeMode".tr,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          radioWidget(
            label: "dynamic".tr,
            controller: settingsController,
            value: ThemeType.dynamic,
          ),
          radioWidget(
              label: "systemDefault".tr,
              controller: settingsController,
              value: ThemeType.system),
          radioWidget(
              label: "dark".tr,
              controller: settingsController,
              value: ThemeType.dark),
          radioWidget(
              label: "light".tr,
              controller: settingsController,
              value: ThemeType.light),
          Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text("cancel".tr),
                ),
                onTap: () => Navigator.of(context).pop(),
              ))
        ]),
      ),
    );
  }
}

class DiscoverContentSelectorDialog extends StatelessWidget {
  const DiscoverContentSelectorDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsScreenController>();
    return CommonDialog(
      child: Container(
        height: 300,
        //color: Theme.of(context).cardColor,
        padding: const EdgeInsets.only(top: 30, left: 5, right: 30, bottom: 10),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.only(left: 20.0, bottom: 5),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "setDiscoverContent".tr,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          SizedBox(
            height: 180,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  radioWidget(
                      label: "quickpicks".tr,
                      controller: settingsController,
                      value: "QP"),
                  radioWidget(
                      label: "topmusicvideos".tr,
                      controller: settingsController,
                      value: "TMV"),
                  radioWidget(
                      label: "trending".tr,
                      controller: settingsController,
                      value: "TR"),
                  radioWidget(
                      label: "basedOnLast".tr,
                      controller: settingsController,
                      value: "BOLI"),
                ],
              ),
            ),
          ),
          const Expanded(child: SizedBox()),
          Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text("cancel".tr),
                ),
                onTap: () => Navigator.of(context).pop(),
              ))
        ]),
      ),
    );
  }
}

class ProxyAddressDialog extends StatefulWidget {
  const ProxyAddressDialog({super.key});

  @override
  State<ProxyAddressDialog> createState() => _ProxyAddressDialogState();
}

class _ProxyAddressDialogState extends State<ProxyAddressDialog> {
  late final TextEditingController _textController;
  final settingsController = Get.find<SettingsScreenController>();

  @override
  void initState() {
    super.initState();
    _textController =
        TextEditingController(text: settingsController.proxyAddress.value);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      child: Container(
        padding: const EdgeInsets.only(top: 30, left: 20, right: 20, bottom: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "proxyAddress".tr,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _textController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: "proxyAddressHint".tr,
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text("cancel".tr),
                ),
                TextButton(
                  onPressed: () {
                    settingsController
                        .setProxyAddress(_textController.text.trim());
                    Navigator.of(context).pop();
                  },
                  child: Text("save".tr),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget radioWidget(
    {required String label,
    required SettingsScreenController controller,
    required value}) {
  return Obx(() {
    final groupValue = value.runtimeType == ThemeType
        ? controller.themeModetype.value
        : controller.discoverContentType.value;
    final isSelected = groupValue == value;
    return ListTile(
      visualDensity: const VisualDensity(vertical: -4),
      onTap: () {
        if (value.runtimeType == ThemeType) {
          controller.onThemeChange(value);
        } else {
          controller.onContentChange(value);
          Navigator.of(Get.context!).pop();
        }
      },
      // No ThemeType.dark, o ponto selecionado ganha o gradiente
      // verde→rosa Apple Music em vez do verde sólido padrão do Radio;
      // nos demais temas (e quando não selecionado) continua o Radio
      // nativo de sempre, com o mesmo onChanged de antes.
      leading: Builder(builder: (context) {
        if (isSelected && isExactDarkTheme(context)) {
          return const _GradientRadioDot();
        }
        return Radio(
            value: value,
            groupValue: groupValue,
            onChanged: value.runtimeType == ThemeType
                ? controller.onThemeChange
                : controller.onContentChange);
      }),
      title: Text(label),
    );
  });
}

/// Réplica visual do "ponto" de um Radio selecionado (anel + centro
/// preenchido), só que com o gradiente verde→rosa Apple Music em vez de
/// uma cor sólida — Flutter não permite gradiente direto em Radio/Switch,
/// então desenhamos o mesmo desenho com Containers circulares empilhados.
class _GradientRadioDot extends StatelessWidget {
  const _GradientRadioDot({this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: const BoxDecoration(
                shape: BoxShape.circle, gradient: kAccentGradient),
          ),
          Container(
            width: size - 4,
            height: size - 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Mesma cor de fundo do diálogo no Dark (kSurfaceElevated),
              // criando o efeito de "anel" ao redor do centro.
              color: Theme.of(context).dialogBackgroundColor,
            ),
          ),
          Container(
            width: (size - 4) * 0.5,
            height: (size - 4) * 0.5,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, gradient: kAccentGradient),
          ),
        ],
      ),
    );
  }
}
