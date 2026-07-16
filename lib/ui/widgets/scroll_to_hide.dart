import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'bottom_nav_bar.dart';

class ScrollToHideWidget extends StatelessWidget {
  const ScrollToHideWidget(
      {super.key, required this.isVisible, required this.child});
  final Widget child;
  final bool isVisible;

  @override
  Widget build(BuildContext context) {
    // IMPORTANTE: essa altura precisa bater exatamente com a soma das
    // margens + altura da pílula em bottom_nav_bar.dart
    // (top + pill + bottom + safe-area). Se for maior, o Container(height:
    // kFloatingNavBarHeight) de dentro do BottomNavBar recebe constraints
    // tight do AnimatedContainer e é esticado além de 52dp, perdendo o
    // visual compacto e refinado da pílula.
    final floatingNavBarTotalHeight = kFloatingNavBarTopMargin +
        kFloatingNavBarHeight +
        kFloatingNavBarBottomMargin +
        Get.mediaQuery.viewPadding.bottom;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: isVisible ? floatingNavBarTotalHeight : 0.0,
      child: child,
    );
  }
}
