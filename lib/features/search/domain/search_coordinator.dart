import 'dart:async';
import '../../../core/models/track.dart';
import '../data/i_music_source.dart';

/// Não sabe COMO cada API funciona. Só sabe agregar, ordenar e emitir.
class SearchCoordinator {
  final List<IMusicSource> _sources;

  SearchCoordinator(this._sources);

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
      source.search(query).then((tracks) {
        aggregated.addAll(tracks);
        _sortByQuality(aggregated);
        if (!controller.isClosed) controller.add(List.unmodifiable(aggregated));
      }).catchError((_) {
        // fonte falhou → ignora silenciosamente, outras continuam
      }).whenComplete(() {
        pending--;
        if (pending == 0 && !controller.isClosed) controller.close();
      });
    }

    return controller.stream;
  }

  void _sortByQuality(List<Track> tracks) {
    tracks.sort((a, b) => (b.bitrateKbps ?? 0).compareTo(a.bitrateKbps ?? 0));
  }
}
