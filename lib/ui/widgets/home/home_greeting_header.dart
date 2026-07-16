import 'package:flutter/material.dart';

/// Saudação dinâmica no topo da Home ("Bom dia" / "Boa tarde" / "Boa
/// noite"), calculada pela hora do aparelho. Puramente visual, sem
/// nenhum ícone de ação — a navegação continua só pela navbar lateral/
/// inferior, como já era.
///
/// Texto ainda não passa pelo sistema de tradução (.tr) do app: são
/// strings novas, e o arquivo lib/utils/get_localization.dart é
/// gerado automaticamente a partir de localization/*.json (não deve
/// ser editado à mão). Se quiser essas strings traduzíveis, é só
/// adicionar as chaves em localization/en.json e localization/pt.json
/// e rodar o gerador de localização do projeto.
class HomeGreetingHeader extends StatelessWidget {
  const HomeGreetingHeader({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Bom dia";
    if (hour < 18) return "Boa tarde";
    return "Boa noite";
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 10),
      child: Text(
        _greeting(),
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
