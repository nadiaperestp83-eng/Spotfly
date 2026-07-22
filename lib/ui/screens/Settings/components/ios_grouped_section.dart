import 'package:flutter/material.dart';

/// Paleta inspirada no branding do iTunes/Apple Music (tons de
/// rosa-vermelho). Usada nos pequenos "chips" de ícone de cada grupo,
/// reproduzindo o estilo "grouped list" das Ajustes do iOS mas mantendo
/// a identidade visual rosa/vermelha que o app já usava.
const List<Color> kiTunesAccentColors = [
  Color(0xFFFA2D48), // Apple Music pink-red (personalisation)
  Color(0xFFFF375F), // content
  Color(0xFFFC3C44), // music & playback
  Color(0xFFE0115F), // download
  Color(0xFFD70015), // backup & restore
  Color(0xFFC4001D), // misc
  Color(0xFF8E0F27), // proxy
  Color(0xFFFA2D48), // app info
];

/// Container "agrupado" estilo iOS Ajustes: fundo branco puro,
/// borderRadius de 12, sem margem entre os itens internos e um
/// Divider(indent: 50) fino separando cada item — nunca depois do
/// último.
class IosGroupedSection extends StatelessWidget {
  final List<Widget> children;

  const IosGroupedSection({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    // Antes o card era sempre branco puro, mesmo no Dark; agora usa a cor
    // de card do tema ativo (branco no light, kSurfaceElevated no dark).
    final cardColor = Theme.of(context).cardColor;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: cardColor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < children.length; i++) ...[
              children[i],
              if (i != children.length - 1)
                Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: 50,
                  color: isLight
                      ? const Color(0xFFC6C6C8)
                      : Colors.white.withOpacity(0.12),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
