import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/screens/Home/home_screen_controller.dart';
import 'package:harmonymusic/ui/utils/theme_controller.dart'
    show kAccentColor, kAppleAccentColor;

/// Altura da pílula em si (sem margens/safe-area). Mantida em constante
/// para reaproveitar em `ScrollToHideWidget` (home.dart), evitando números
/// "mágicos" duplicados em vários arquivos.
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
///    baixo).
/// 4. O `Container` com `Colors.white.withOpacity(0.06)` + borda sutil
///    é o "vidro": uma cor quase transparente sobre o blur para dar
///    profundidade sem virar um bloco opaco.
///
/// IMPORTANTE — por que não usamos mais o widget `NavigationBar` do
/// Material 3 aqui: o `NavigationBar` do Flutter tem uma altura mínima
/// intrínseca pensada para 80dp (ícone + indicador em pílula + label).
/// Quando forçamos `height: 52` (via tema) para caber na barra flutuante,
/// o indicador (StadiumBorder) mantém o padding interno calculado pra
/// 80dp e passa a ficar cortado/desalinhado — os ícones "saem" da
/// pílula de destaque. Em vez de lutar contra esse comportamento interno,
/// construímos a barra manualmente com um `Row` de itens: temos controle
/// total do alinhamento vertical e, de brinde, o resultado fica mais fiel
/// ao Spotify real, que não usa uma pílula de fundo no item selecionado —
/// só muda a cor do ícone/label.
class BottomNavBar extends StatelessWidget {
  const BottomNavBar({super.key});

  static const List<_NavItem> _items = [
    _NavItem(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      labelKey: 'home',
    ),
    _NavItem(
      icon: Icons.search_outlined,
      selectedIcon: Icons.search_rounded,
      labelKey: 'search',
    ),
    _NavItem(
      icon: Icons.library_music_outlined,
      selectedIcon: Icons.library_music_rounded,
      labelKey: 'library',
    ),
    _NavItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
      labelKey: 'settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final homeScreenController = Get.find<HomeScreenController>();
    // viewPadding.bottom = altura da barra de gestos do Android; some
    // dinamicamente com o inset do dispositivo.
    final gestureInset = MediaQuery.of(context).viewPadding.bottom;

    // O tema "light" (Ajustes/Apple Music) é o único com
    // `brightness: Brightness.light` (ver theme_controller.dart); os temas
    // "dark" e "dynamic" usam Brightness.dark. É esse flag que decide o
    // "look" da navbar — sem depender de nenhum estado próprio aqui.
    final isLightTheme = Theme.of(context).brightness == Brightness.light;

    // Cor de destaque do item selecionado: vermelho/rosa "iTunes Music"
    // no tema light/iOS; verde (Spotify) nos temas dark/dynamic — mantido
    // de propósito para não mexer no visual desses dois temas agora.
    final selectedColor = isLightTheme ? kAppleAccentColor : kAccentColor;
    final unselectedColor =
        isLightTheme ? Colors.black45 : Colors.white60;

    // Vidro fosco: branco no tema light (não mais preto fixo), preto no
    // dark/dynamic — mesmo efeito de blur, só troca a base de cor.
    final glassColor = isLightTheme
        ? Colors.white.withOpacity(0.75)
        : const Color(0xFF121212).withOpacity(0.85);
    final glassBorderColor = isLightTheme
        ? Colors.black.withOpacity(0.08)
        : Colors.white.withOpacity(0.10);

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
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: kFloatingNavBarHeight,
            decoration: BoxDecoration(
              color: glassColor,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: glassBorderColor,
                width: 0.6,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Obx(() {
              final selectedIndex = homeScreenController.tabIndex.toInt();
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(_items.length, (index) {
                  final item = _items[index];
                  final selected = index == selectedIndex;
                  return Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () =>
                            homeScreenController.onBottonBarTabSelected(index),
                        child: SizedBox(
                          height: kFloatingNavBarHeight,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                selected ? item.selectedIcon : item.icon,
                                size: 22,
                                color: selected
                                    ? selectedColor
                                    : unselectedColor,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                modifyNgetlabel(item.labelKey.tr),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: selected
                                      ? selectedColor
                                      : unselectedColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              );
            }),
          ),
        ),
      ),
    );
  }

  static String modifyNgetlabel(String label) {
    if (label.length > 9) {
      return "${label.substring(0, 8)}..";
    }
    return label;
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.labelKey,
  });
  final IconData icon;
  final IconData selectedIcon;
  final String labelKey;
}
