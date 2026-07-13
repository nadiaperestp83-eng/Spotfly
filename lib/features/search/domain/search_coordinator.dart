import 'dart:async';

import '../../../core/metadata/i_metadata_provider.dart';
import '../../../core/models/home_section.dart';
import '../../../core/models/track.dart';
import '../data/i_music_source.dart';

/// Orquestrador central. Não sabe COMO cada fonte funciona (HTTP,
/// scraping, SDK...), só conhece a interface IMusicSource.
///
/// Estratégia: fallback automático e sequencial, na ordem definida em
/// musicSourcesProvider (ver core/providers/providers.dart). Tenta a
/// fonte 1; se der erro/timeout/vazio, tenta a fonte 2; e assim por
/// diante. Retorna assim que a primeira fonte responder com resultado.
/// A UI nunca sabe qual fonte respondeu — só recebe List<Track>.
class SearchCoordinator {
  final List<IMusicSource> _sources;
  final IMetadataProvider? _metadataProvider;

  static const _sourceTimeout = Duration(seconds: 12);
  static const _enrichTimeout = Duration(seconds: 3);

  SearchCoordinator(this._sources, {IMetadataProvider? metadataProvider})
      : _metadataProvider = metadataProvider;

  Future<List<Track>> search(String query) async {
    if (query.trim().isEmpty) return [];

    Object? lastError;
    StackTrace? lastStack;

    for (final source in _sources) {
      try {
        final tracks = await source.search(query).timeout(_sourceTimeout);
        if (tracks.isNotEmpty) {
          final enriched = await _enrichBatch(tracks);
          _sortByQuality(enriched);
          return enriched;
        }
        // Fonte respondeu mas não achou nada: tenta a próxima mesmo assim.
      } catch (e, st) {
        // Fonte falhou (rede, timeout, parsing...). Nunca propaga aqui —
        // isso é o que evita o loop/travamento. Só guarda pra decidir
        // depois se TODAS falharam.
        lastError = e;
        lastStack = st;
        continue;
      }
    }

    if (lastError == null) {
      // Todas as fontes responderam, nenhuma achou nada: resultado
      // legítimo vazio, não é erro.
      return [];
    }

    // Todas as fontes falharam de fato: propaga o último erro para o
    // AsyncNotifier, que vai virar AsyncError na UI (nunca fica preso
    // em loading).
    Error.throwWithStackTrace(lastError, lastStack ?? StackTrace.current);
  }

  /// Mesma estratégia de fallback sequencial, usada pela Home.
  Future<List<HomeSection>> getHome() async {
    Object? lastError;
    StackTrace? lastStack;

    for (final source in _sources) {
      try {
        final sections = await source.getHomeSections().timeout(_sourceTimeout);
        if (sections.isNotEmpty) return sections;
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        continue;
      }
    }

    if (lastError == null) return [];
    Error.throwWithStackTrace(lastError, lastStack ?? StackTrace.current);
  }

  Future<List<Track>> _enrichBatch(List<Track> tracks) async {
    final provider = _metadataProvider;
    if (provider == null || tracks.isEmpty) return tracks;

    return Future.wait(tracks.map((track) async {
      try {
        return await provider.enrich(track).timeout(_enrichTimeout);
      } catch (_) {
        return track; // mantém a versão "crua" — enriquecimento é best-effort
      }
    }));
  }

  void _sortByQuality(List<Track> tracks) {
    tracks.sort((a, b) => (b.bitrateKbps ?? 0).compareTo(a.bitrateKbps ?? 0));
  }
}
