import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:webfeed_plus/webfeed_plus.dart';

import '../../../../core/models/podcast_episode.dart';
import '../../../../core/models/search_result.dart';
import '../../../../core/models/track.dart';
import '../../../../utils/helper.dart';
import '../i_music_source.dart';

/// Fonte "iTunes Search API + RSS": fonte PRIMÁRIA das 3 seções
/// narrativas da Home (ver AudioContentService), com Internet Archive
/// como fallback automático. Mesmo padrão ISOLADO de InternetArchiveSource
/// e JamendoSource: não entra no orquestrador de busca normal
/// (musicSourcesProvider) — só é chamada via AudioContentService e
/// registrada à parte em playbackResolverProvider (ver
/// core/providers/providers.dart) só pra o player conseguir resolver a
/// URL de áudio dessas faixas.
///
/// Fluxo (2 passos, porque a Search API só conhece o PODCAST, não os
/// episódios individuais):
/// 1) https://itunes.apple.com/search?media=podcast -> lista de
///    podcasts candidatos, cada um com seu `feedUrl` (RSS).
/// 2) Baixa e faz parse do RSS de cada candidato (webfeed_plus) até
///    juntar [resultLimit] episódios cuja duração (itunes:duration)
///    caia dentro da faixa pedida.
class ItunesSource implements IMusicSource {
  static const _searchUrl = 'https://itunes.apple.com/search';
  static const _searchTimeout = Duration(seconds: 5);
  static const _feedTimeout = Duration(seconds: 6);

  @override
  String get sourceId => 'itunes';

  @override
  Future<SearchResult> search(
    String query, {
    String? filter,
    String? filterParams,
    int limit = 30,
  }) async {
    // Não faz parte da busca normal do app — só usado pelas seções
    // narrativas da Home via searchPodcastEpisodes() (por baixo do
    // AudioContentService).
    return const SearchResult(sourceId: 'itunes');
  }

  @override
  Future<SearchResult> searchContinuation(
    Map<String, dynamic> continuationParams, {
    int limit = 10,
  }) async {
    return const SearchResult(sourceId: 'itunes');
  }

  @override
  Future<List<dynamic>> getHomeContent({int limit = 4}) async => const [];

  @override
  Future<String> resolveStreamUrl(Track track) async {
    // A URL do mp3 já veio pronta do <enclosure> do RSS durante a
    // busca (sourceTrackId guarda essa URL direto), então tocar essa
    // faixa não exige nova chamada de rede.
    return track.sourceTrackId;
  }

  /// Busca episódios de podcast em português via iTunes Search API,
  /// filtrando por duração (em segundos). Nunca lança timeout pra
  /// fora: qualquer estouro de tempo (busca OU parse de feed) deve ser
  /// tratado pelo chamador (AudioContentService) como "iTunes falhou,
  /// cai pro fallback".
  Future<List<PodcastEpisode>> searchPodcastEpisodes({
    required String searchTerm,
    required int minSeconds,
    required int maxSeconds,
    int podcastCandidates = 3,
    int resultLimit = 10,
    String country = 'BR',
  }) async {
    final episodes = <PodcastEpisode>[];

    final searchUri = Uri.parse(_searchUrl).replace(queryParameters: {
      'term': searchTerm,
      'media': 'podcast',
      'entity': 'podcast',
      'country': country,
      'limit': podcastCandidates.toString(),
    });

    final searchResponse = await http.get(searchUri).timeout(_searchTimeout);
    if (searchResponse.statusCode != 200) return episodes;

    final body = jsonDecode(searchResponse.body) as Map<String, dynamic>;
    final results = (body['results'] as List<dynamic>? ?? const []);
    if (results.isEmpty) return episodes;

    for (final r in results) {
      if (episodes.length >= resultLimit) break;
      final podcast = r as Map<String, dynamic>;
      final feedUrl = podcast['feedUrl'] as String?;
      if (feedUrl == null) continue;

      try {
        final feedResponse =
            await http.get(Uri.parse(feedUrl)).timeout(_feedTimeout);
        if (feedResponse.statusCode != 200) continue;

        final feed = RssFeed.parse(feedResponse.body);
        final podcastName = feed.title ??
            (podcast['collectionName'] as String?) ??
            'Podcast';
        // Artwork vem do JSON da Search API (sempre confiável), não do
        // RSS — reaproveitada em todos os episódios desse podcast.
        final artwork = (podcast['artworkUrl600'] as String?) ??
            (podcast['artworkUrl100'] as String?) ??
            '';

        for (final item in feed.items ?? const <RssItem>[]) {
          if (episodes.length >= resultLimit) break;

          final mp3Url = item.enclosure?.url;
          final duration = item.itunes?.duration;
          if (mp3Url == null || duration == null) continue;
          if (duration.inSeconds < minSeconds ||
              duration.inSeconds > maxSeconds) {
            continue;
          }

          episodes.add(PodcastEpisode(
            id: 'itunes_${item.guid ?? mp3Url}',
            title: item.title ?? podcastName,
            description: item.description,
            artist: podcastName,
            audioUrl: mp3Url,
            artworkUrl: artwork,
            duration: duration,
            sourceId: sourceId,
          ));
        }
      } catch (e) {
        // Esse feed específico falhou (RSS inválido, off-line, etc.):
        // pula pro próximo candidato sem derrubar a busca inteira.
        printERROR('ItunesSource: feed "$feedUrl" falhou: $e');
        continue;
      }
    }

    return episodes;
  }
}
