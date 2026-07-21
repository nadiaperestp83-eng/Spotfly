import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CustomExpansionTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  /// Cor do pequeno "chip" quadrado atrás do ícone, no estilo dos
  /// grupos coloridos das Ajustes do iOS (aqui usando a paleta
  /// rosa/vermelha do iTunes/Apple Music).
  final Color accentColor;

  const CustomExpansionTile({
    super.key,
    required this.children,
    required this.icon,
    required this.title,
    this.accentColor = const Color(0xFFFA2D48),
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      // O ExpansionTile desenha uma linha divisória própria acima/abaixo
      // quando expandido; como o agrupamento (Divider indent: 50) já é
      // feito pelo IosGroupedSection, removemos essa linha extra aqui.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        backgroundColor: Colors.white,
        collapsedBackgroundColor: Colors.white,
        iconColor: Colors.grey,
        collapsedIconColor: Colors.grey,
        title: Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w400,
            color: Colors.black,
          ),
        ),
        leading: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: accentColor,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        children: children,
      ),
    );
  }
}
