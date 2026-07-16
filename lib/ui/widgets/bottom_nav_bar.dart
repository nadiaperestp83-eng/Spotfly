import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/screens/Home/home_screen_controller.dart';

/// BottomNavBar premium (Material 3 `NavigationBar`).
///
/// Toda a aparência visual (fundo, indicador em pílula, cores de ícone e
/// label selecionado/não selecionado) vem centralizada do
/// `navigationBarTheme` definido em `ThemeData` (ver theme_controller.dart),
/// para que o mesmo estilo seja aplicado de forma consistente em qualquer
/// tela que use este widget. Aqui só definimos a estrutura (destinos) e os
/// pares de ícone outline/filled que habilitam a transição animada nativa
/// do NavigationBar entre estado selecionado e não selecionado.
class BottomNavBar extends StatelessWidget {
  const BottomNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    final homeScreenController = Get.find<HomeScreenController>();
    return Obx(() => NavigationBar(
          onDestinationSelected: homeScreenController.onBottonBarTabSelected,
          selectedIndex: homeScreenController.tabIndex.toInt(),
          // Herda tudo (cor de fundo, indicador em pílula, elevação zero,
          // surfaceTint transparente) do NavigationBarThemeData do tema
          // ativo — não sobrescrevemos aqui para manter uma única fonte
          // de verdade de estilo.
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
        ));
  }

  String modifyNgetlabel(String label) {
    if (label.length > 9) {
      return "${label.substring(0, 8)}..";
    }
    return label;
  }
}
