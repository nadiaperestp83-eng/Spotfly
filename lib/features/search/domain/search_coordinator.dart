import 'dart:async';

import '../../../core/metadata/i_metadata_provider.dart';
import '../../../core/models/track.dart';
import '../data/i_music_source.dart';

/// Não sabe COMO cada API funciona (HTTP, scraping, SDK...).
/// Só sabe: recebe uma lista de IMusicSource, dispara em paralelo,
/// agrega por bitrate/performance, enriquece via IMetadataProvider
/// (opcional) e emite via Stream. Não sabe que "Last.fm" existe —
/// só conhece a interface.
class SearchCoordinator {
  final List<IMusicSource> _sources;
  final IMetadataProvider? _metadataProvider;
  static const _enrichTimeout = Duration(seconds: 3);

  SearchCoordinator(this._sources, {IMetadataProvider? metadataProvider})
      : _metadataProvider = metadataProvider;

  Stream<List<Track>> search(String query) {
    final controller = StreamController<List<Track>>();
    final aggregated = <Track>[];
    var pending = _sources.length;

    if (pending == 0) {
      controller.add([]);
      controller.close();
      return controller.stream;
    }

    for (final source in _sources) {
      source.search(query).then((tracks) async {
        final enriched = await _enrichBatch(tracks);

        // Remove versões antigas dos mesmos ids (evita duplicar caso
        // dois lotes cheguem com a mesma faixa) e adiciona as novas.
        aggregated.removeWhere((t) => enriched.any((e) => e.id == t.id));
        aggregated.addAll(enriched);
        _sortByQuality(aggregated);

        if (!controller.isClosed) {
          controller.add(List.unmodifiable(aggregated));
        }
      }).catchError((_) {
        // Fonte falhou: ignora silenciosamente, as demais continuam.
        // Usuário nunca vê "Jamendo indisponível" — é detalhe interno.
      }).whenComplete(() {
        pending--;
        if (pending == 0 && !controller.isClosed) controller.close();
      });
    }

    return controller.stream;
  }

  /// Enriquece em paralelo, com timeout individual. Se o provider
  /// falhar ou não estiver configurado, devolve as tracks originais —
  /// nunca derruba a busca por causa do Last.fm estar fora do ar.
  Future<List<Track>> _enrichBatch(List<Track> tracks) async {
    final provider = _metadataProvider;
    if (provider == null || tracks.isEmpty) return tracks;

    final results = await Future.wait(tracks.map((track) async {
      try {
        return await provider.enrich(track).timeout(_enrichTimeout);
      } catch (_) {
        return track; // mantém a versão "crua" dessa faixa
      }
    }));

    return results;
  }

  void _sortByQuality(List<Track> tracks) {
    tracks.sort((a, b) => (b.bitrateKbps ?? 0).compareTo(a.bitrateKbps ?? 0));
  }
}
