import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/models/podcast_episode.dart';
import '../../../../core/models/search_result.dart';
import '../../../../core/models/track.dart';
import '../i_music_source.dart';
import '../../../../utils/helper.dart';

/// Fonte "Listen Notes API": 2º nível do Fallback Híbrido das 3 seções
/// narrativas da Home (ver AudioContentService) — só entra em ação se
/// a iTunes Search API falhar/não achar nada. Se o Listen Notes também
/// falhar, o Internet Archive continua como 3º nível (última rede de
/// segurança).
///
/// Bem mais simples que o fluxo do iTunes: o endpoint /search já
/// devolve o episódio pronto (título, descrição, mp3 em `audio`,
/// duração em `audio_length_sec`) — não precisa baixar/parsear RSS.
/// Documentação: https://www.podcastapi.com/
///
/// Mesmo padrão ISOLADO de ItunesSource/InternetArchiveSource: não
/// entra no orquestrador de busca normal (musicSourcesProvider), só é
/// usada via AudioContentService e registrada à parte em
/// playbackResolverProvider (core/providers/providers.dart) pra o
/// player conseguir resolver a URL de áudio.
///
/// A chave é lida de `--dart-define=LISTENNOTES_API_KEY=...`, injetada
/// no build via GitHub Secrets (mesmo padrão de JAMENDO_CLIENT_ID e
/// LASTFM_API_KEY em .github/workflows/build-unsigned.yml) — NUNCA
/// commitada em texto puro no repositório.
class ListenNotesSource implements IMusicSource {
  static const _searchUrl = 'https://listen-api.listennotes.com/api/v2/search';
  static const _apiKey = String.fromEnvironment('LISTENNOTES_API_KEY');
  static const _searchTimeout = Duration(seconds: 6);

  @override
  String get sourceId => 'listennotes';

  @override
  Future<SearchResult> search(
    String query, {
    String? filter,
    String? filterParams,
    int limit = 30,
  }) async {
    return const SearchResult(sourceId: 'listennotes');
  }

  @override
  Future<SearchResult> searchContinuation(
    Map<String, dynamic> continuationParams, {
    int limit = 10,
  }) async {
    return const SearchResult(sourceId: 'listennotes');
  }

  @override
  Future<List<dynamic>> getHomeContent({int limit = 4}) async => const [];

  @override
  Future<String> resolveStreamUrl(Track track) async {
    // O mp3 já veio pronto no campo "audio" da resposta do /search,
    // guardado em sourceTrackId — tocar não exige nova chamada.
    return track.sourceTrackId;
  }

  /// Busca episódios de podcast via Listen Notes /search
  /// (type=episode), filtrando por duração. O parâmetro `len_min`/
  /// `len_max` da API é em MINUTOS (granularidade grosseira), então
  /// depois de receber a resposta ainda refiltra em segundos
  /// (audio_length_sec) contra [minSeconds]/[maxSeconds] pra ficar
  /// exato.
  ///
  /// Se `LISTENNOTES_API_KEY` não foi definida no build (--dart-define
  /// ausente), devolve lista vazia sem tentar a chamada — isso deixa o
  /// AudioContentService pular direto pro Internet Archive, em vez de
  /// falhar com erro de autenticação em toda build sem a chave (ex.:
  /// builds locais de outros devs, sem acesso aos Secrets do CI).
  Future<List<PodcastEpisode>> searchPodcastEpisodes({
    required String searchTerm,
    required int minSeconds,
    required int maxSeconds,
    int resultLimit = 10,
    String language = 'Portuguese',
    String region = 'br',
  }) async {
    if (_apiKey.isEmpty) return const [];

    final lenMinMinutes = (minSeconds / 60).floor();
    final lenMaxMinutes = (maxSeconds / 60).ceil();

    final uri = Uri.parse(_searchUrl).replace(queryParameters: {
      'q': searchTerm,
      'type': 'episode',
      'page_size': (resultLimit > 10 ? 10 : resultLimit).toString(),
      'language': language,
      'region': region,
      'len_min': lenMinMinutes.toString(),
      'len_max': lenMaxMinutes.toString(),
    });

    final response = await http
        .get(uri, headers: {'X-ListenAPI-Key': _apiKey})
        .timeout(_searchTimeout);
    if (response.statusCode != 200) {
      printERROR(
          'ListenNotesSource: HTTP ${response.statusCode} ao buscar "$searchTerm"');
      return const [];
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (body['results'] as List<dynamic>? ?? const []);

    final episodes = <PodcastEpisode>[];
    for (final r in results) {
      if (episodes.length >= resultLimit) break;
      final ep = r as Map<String, dynamic>;

      final audioUrl = ep['audio'] as String?;
      final durationSeconds = ep['audio_length_sec'] as int?;
      if (audioUrl == null || durationSeconds == null) continue;
      // Refiltro exato em segundos: len_min/len_max da API são em
      // minutos e podem devolver episódios um pouco fora da faixa.
      if (durationSeconds < minSeconds || durationSeconds > maxSeconds) {
        continue;
      }

      final podcast = ep['podcast'] as Map<String, dynamic>?;
      final podcastName =
          (podcast?['title_original'] as String?) ?? 'Podcast';

      episodes.add(PodcastEpisode(
        id: 'listennotes_${ep['id']}',
        title: (ep['title_original'] as String?) ?? podcastName,
        description: ep['description_original'] as String?,
        artist: podcastName,
        audioUrl: audioUrl,
        artworkUrl: (ep['thumbnail'] as String?) ?? '',
        duration: Duration(seconds: durationSeconds),
        sourceId: sourceId,
      ));
    }

    return episodes;
  }
}
