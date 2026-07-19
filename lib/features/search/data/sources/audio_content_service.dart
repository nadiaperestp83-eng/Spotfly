import 'dart:async';

import '../../../../core/models/podcast_episode.dart';
import '../../../../utils/helper.dart';
import 'internet_archive_source.dart';
import 'itunes_source.dart';
import 'listen_notes_source.dart';

/// "Fallback Híbrido" pras 3 seções narrativas da Home (Minutos de
/// Reflexão, Contos da Noite, Poesia Sonora) — chamado por
/// HomeScreenController._loadNarrativeSection(). A seção "Mais
/// tocadas" (YouTube/Trending) NÃO passa por aqui e é FIXA na Home,
/// sem nenhum fallback — continua exatamente como está.
///
/// Estratégia de prioridade (3 níveis):
/// 1º ItunesSource (iTunes Search API -> feedUrl -> parse do RSS via
///    webfeed_plus). Timeout curto (5s) cobrindo a tentativa inteira.
/// 2º ListenNotesSource (Listen Notes /search, type=episode — já
///    devolve o episódio pronto, sem precisar de RSS). Só entra em
///    ação se o iTunes falhar/não achar nada. Se a chave
///    LISTENNOTES_API_KEY não estiver configurada no build, essa
///    fonte já se auto-desativa (devolve vazio na hora, sem tentar
///    rede) e cai direto pro passo 3.
/// 3º InternetArchiveSource (lógica já existente, sem nenhuma
///    mudança) — última rede de segurança, só se as duas anteriores
///    falharem de verdade.
///
/// Sempre devolve List<PodcastEpisode>: um modelo único, então quem
/// chama (HomeScreenController) não precisa saber nem se importar com
/// qual das três fontes respondeu.
class AudioContentService {
  AudioContentService({
    ItunesSource? itunesSource,
    ListenNotesSource? listenNotesSource,
    InternetArchiveSource? archiveSource,
  })  : _itunesSource = itunesSource ?? ItunesSource(),
        _listenNotesSource = listenNotesSource ?? ListenNotesSource(),
        _archiveSource = archiveSource ?? InternetArchiveSource();

  final ItunesSource _itunesSource;
  final ListenNotesSource _listenNotesSource;
  final InternetArchiveSource _archiveSource;

  /// Cobre a tentativa completa do iTunes (busca + download/parse dos
  /// feeds RSS candidatos). Estourou o prazo -> trata como falha e
  /// vai pro próximo nível (Listen Notes) na hora, sem esperar mais.
  static const _itunesOverallTimeout = Duration(seconds: 5);

  /// Timeout do 2º nível (Listen Notes) — chamada única e simples,
  /// não precisa de tanto tempo quanto o iTunes (que baixa RSS).
  static const _listenNotesTimeout = Duration(seconds: 6);

  /// Timeout do 3º nível/último fallback (Internet Archive). SEM
  /// isso, se o archive.org ficar lento/instável, a seção fica
  /// girando pra sempre — foi exatamente esse bug que apareceu na
  /// primeira versão do Fallback Híbrido (o timeout de 15s que
  /// existia antes, direto no HomeScreenController, tinha ficado pra
  /// trás na migração).
  static const _archiveFallbackTimeout = Duration(seconds: 15);

  /// [itunesTerm]: termo de busca pra iTunes Search API e pro Listen
  /// Notes (media=podcast / type=episode), normalmente mais
  /// simples/amplo que a query avançada do Archive (ex.: "contos
  /// infantis" em vez de uma expressão com subject:/title:).
  /// [archiveQuery]: a query avançada (advancedsearch.php) que as 3
  /// seções já usavam antes — passada direto pro
  /// InternetArchiveSource.searchNarratedAudio() sem nenhuma
  /// alteração, só entra em jogo se as duas fontes anteriores
  /// falharem.
  Future<List<PodcastEpisode>> fetchEpisodes({
    required String itunesTerm,
    required String archiveQuery,
    required int minSeconds,
    required int maxSeconds,
    int resultLimit = 10,
    String itunesCountry = 'BR',
  }) async {
    // 1º nível: iTunes.
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
          'AudioContentService: iTunes falhou, tentando Listen Notes: $e');
    }

    // 2º nível: Listen Notes.
    try {
      final listenNotesEpisodes = await _listenNotesSource
          .searchPodcastEpisodes(
            searchTerm: itunesTerm,
            minSeconds: minSeconds,
            maxSeconds: maxSeconds,
            resultLimit: resultLimit,
          )
          .timeout(_listenNotesTimeout, onTimeout: () => const []);

      if (listenNotesEpisodes.isNotEmpty) return listenNotesEpisodes;
    } catch (e) {
      printERROR(
          'AudioContentService: Listen Notes falhou, caindo pro Internet Archive: $e');
    }

    // 3º nível (última rede de segurança): Internet Archive, lógica já
    // existente sem mudanças — só a conversão pro modelo unificado
    // PodcastEpisode é nova.
    try {
      final tracks = await _archiveSource
          .searchNarratedAudio(
            query: archiveQuery,
            minSeconds: minSeconds,
            maxSeconds: maxSeconds,
            resultLimit: resultLimit,
          )
          .timeout(_archiveFallbackTimeout, onTimeout: () => const []);
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
          'AudioContentService: Internet Archive (fallback final) também falhou: $e');
      return const [];
    }
  }
}
