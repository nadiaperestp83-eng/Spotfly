import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/screens/Home/home_screen_controller.dart';

/// Altura da pílula em si (sem margens/safe-area). Mantida em constante
/// para reaproveitar em `NavigationBarThemeData.height` (theme_controller.dart)
/// e em `ScrollToHideWidget` (home.dart), evitando números "mágicos"
/// duplicados em vários arquivos.
const double kFloatingNavBarHeight = 52.0;
const double kFloatingNavBarHorizontalMargin = 16.0;
const double kFloatingNavBarTopMargin = 8.0;
const double kFloatingNavBarBottomMargin = 8.0;

/// BottomNavBar "flutuante e translúcida" estilo Spotify.
///
/// Como funciona o efeito de vidro fosco (glassmorphism):
/// 1. `Padding` cria as margens (laterais + a safe-area do gesto do
///    Android) que fazem a barra "flutuar" sem tocar as bordas da tela.
/// 2. `ClipRRect` arredonda os cantos e, crucialmente, recorta o
///    `BackdropFilter` para dentro desse formato de pílula — sem o
///    ClipRRect o blur vazaria como um retângulo.
/// 3. `BackdropFilter(ImageFilter.blur(...))` borra tudo que está
///    renderizado ATRÁS deste widget (a lista de conteúdo rolando por
///    baixo), efeito que só existe porque a NavigationBar em si é
///    transparente (ver `navigationBarTheme` em theme_controller.dart).
/// 4. O `Container` com `Colors.white.withOpacity(0.06)` + borda sutil
///    é o "vidro": uma cor quase transparente sobre o blur para dar
///    profundidade sem virar um bloco opaco.
class BottomNavBar extends StatelessWidget {
  const BottomNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    final homeScreenController = Get.find<HomeScreenController>();
    // viewPadding.bottom = altura da barra de gestos do Android; some
    // dinamicamente com o inset do dispositivo.
    final gestureInset = MediaQuery.of(context).viewPadding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        kFloatingNavBarHorizontalMargin,
        kFloatingNavBarTopMargin,
        kFloatingNavBarHorizontalMargin,
        kFloatingNavBarBottomMargin + gestureInset,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: kFloatingNavBarHeight,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: Colors.white.withOpacity(0.10),
                width: 0.6,
              ),
            ),
            // clipBehavior garante que o indicador em pílula do
            // NavigationBar não vaze para fora dos cantos arredondados.
            clipBehavior: Clip.antiAlias,
            child: Obx(() => NavigationBar(
                  onDestinationSelected:
                      homeScreenController.onBottonBarTabSelected,
                  selectedIndex: homeScreenController.tabIndex.toInt(),
                  destinations: [
                    NavigationDestination(
                      icon: const Icon(Icons.home_outlined),
                      selectedIcon: const Icon(Icons.home_rounded),
                      label: modifyNgetlabel('home'.tr),
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.search_outlined),
                      selectedIcon: const Icon(Icons.search_rounded),
                      label: modifyNgetlabel('search'.tr),
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.library_music_outlined),
                      selectedIcon: const Icon(Icons.library_music_rounded),
                      label: modifyNgetlabel('library'.tr),
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.settings_outlined),
                      selectedIcon: const Icon(Icons.settings_rounded),
                      label: modifyNgetlabel('settings'.tr),
                    ),
                  ],
                )),
          ),
        ),
      ),
    );
  }

  String modifyNgetlabel(String label) {
    if (label.length > 9) {
      return "${label.substring(0, 8)}..";
    }
    return label;
  }
}
