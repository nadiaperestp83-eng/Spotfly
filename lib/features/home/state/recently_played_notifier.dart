import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../models/media_Item_builder.dart';

/// Expõe o histórico de "recém tocadas" como estado Riverpod reativo
/// para a Home.
///
/// NÃO cria nenhum armazenamento novo: lê a MESMA Hive box "LIBRP" que
/// PlayerController._addToRP já mantém a cada troca de música (é a
/// mesma base de dados por trás da playlist especial "Recently Played"
/// da Library). Isso evita ter duas fontes de verdade divergentes para
/// a mesma informação.
///
/// Reativo: escuta Box.listenable(), então assim que uma nova música
/// toca, o card "Recent played" da Home atualiza sozinho — sem precisar
/// de pull-to-refresh nem de recarregar a tela.
class RecentlyPlayedNotifier extends AsyncNotifier<List<MediaItem>> {
  Box? _box;
  VoidCallback? _listener;

  @override
  Future<List<MediaItem>> build() async {
    _box =
        Hive.isBoxOpen("LIBRP") ? Hive.box("LIBRP") : await Hive.openBox("LIBRP");

    _listener = () {
      state = AsyncData(_readFromBox());
    };
    _box!.listenable().addListener(_listener!);

    ref.onDispose(() {
      if (_listener != null) {
        _box?.listenable().removeListener(_listener!);
      }
    });

    return _readFromBox();
  }

  /// A box guarda do mais antigo pro mais novo (PlayerController._addToRP
  /// usa box.add, que sempre insere no fim) — aqui invertemos pra devolver
  /// do mais recente pro mais antigo, que é a ordem que a Home precisa.
  List<MediaItem> _readFromBox() {
    final box = _box;
    if (box == null || box.isEmpty) return [];
    return box.values
        .toList()
        .reversed
        .map((e) =>
            MediaItemBuilder.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}

final recentlyPlayedProvider =
    AsyncNotifierProvider<RecentlyPlayedNotifier, List<MediaItem>>(
        RecentlyPlayedNotifier.new);
