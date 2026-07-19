import 'dart:async';

import '../../../../core/models/podcast_episode.dart';
import '../../../../utils/helper.dart';
import 'internet_archive_source.dart';
import 'itunes_source.dart';

/// "Fallback Híbrido" pras 3 seções narrativas da Home (Minutos de
/// Reflexão, Contos da Noite, Poesia Sonora) — chamado por
/// HomeScreenController._loadNarrativeSection(). A seção "Mais
/// tocadas" (YouTube/Trending) NÃO passa por aqui, continua
/// exatamente como estava antes.
///
/// Estratégia de prioridade:
/// 1º ItunesSource (iTunes Search API -> feedUrl -> parse do RSS via
///    webfeed_plus). Timeout curto (5s) cobrindo a tentativa inteira
///    (busca + parse dos feeds candidatos) — se estourar OU não achar
///    nenhum episódio dentro da faixa de duração pedida, cai pro
///    fallback imediatamente.
/// 2º InternetArchiveSource (lógica já existente, sem nenhuma
///    mudança) — só entra em ação se o iTunes falhar de verdade.
///
/// Sempre devolve List<PodcastEpisode>: um modelo único, então quem
/// chama (HomeScreenController) não precisa saber nem se importar com
/// qual das duas fontes respondeu.
class AudioContentService {
  AudioContentService({
    ItunesSource? itunesSource,
    InternetArchiveSource? archiveSource,
  })  : _itunesSource = itunesSource ?? ItunesSource(),
        _archiveSource = archiveSource ?? InternetArchiveSource();

  final ItunesSource _itunesSource;
  final InternetArchiveSource _archiveSource;

  /// Cobre a tentativa completa do iTunes (busca + download/parse dos
  /// feeds RSS candidatos). Estourou o prazo -> trata como falha e
  /// aciona o Internet Archive na hora, sem esperar mais.
  static const _itunesOverallTimeout = Duration(seconds: 5);

  /// [itunesTerm]: termo de busca pra iTunes Search API (media=podcast),
  /// normalmente mais simples/amplo que a query avançada do Archive
  /// (ex.: "contos infantis" em vez de uma expressão com subject:/title:).
  /// [archiveQuery]: a query avançada (advancedsearch.php) que as 3
  /// seções já usavam antes — passada direto pro
  /// InternetArchiveSource.searchNarratedAudio() sem nenhuma alteração,
  /// só entra em jogo se o iTunes falhar.
  Future<List<PodcastEpisode>> fetchEpisodes({
    required String itunesTerm,
    required String archiveQuery,
    required int minSeconds,
    required int maxSeconds,
    int resultLimit = 10,
    String itunesCountry = 'BR',
  }) async {
    try {
      final itunesEpisodes = await _itunesSource
          .searchPodcastEpisodes(
            searchTerm: itunesTerm,
            minSeconds: minSeconds,
            maxSeconds: maxSeconds,
            resultLimit: resultLimit,
            country: itunesCountry,
          )
          .timeout(_itunesOverallTimeout, onTimeout: () => const []);

      if (itunesEpisodes.isNotEmpty) return itunesEpisodes;
    } catch (e) {
      printERROR(
          'AudioContentService: iTunes falhou, caindo pro Internet Archive: $e');
    }

    // Fallback: Internet Archive, lógica já existente sem mudanças —
    // só a conversão pro modelo unificado PodcastEpisode é nova.
    try {
      final tracks = await _archiveSource.searchNarratedAudio(
        query: archiveQuery,
        minSeconds: minSeconds,
        maxSeconds: maxSeconds,
        resultLimit: resultLimit,
      );
      return tracks
          .map((t) => PodcastEpisode(
                id: 'internetarchive_${t.sourceTrackId}',
                title: t.title,
                artist: t.artist,
                audioUrl: t.sourceTrackId,
                artworkUrl: t.artworkUrl,
                duration: t.duration,
                sourceId: 'internetarchive',
              ))
          .toList();
    } catch (e) {
      printERROR(
          'AudioContentService: Internet Archive (fallback) também falhou: $e');
      return const [];
    }
  }
}
