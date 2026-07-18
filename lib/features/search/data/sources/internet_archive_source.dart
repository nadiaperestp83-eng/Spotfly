import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:http/http.dart' as http;

import '../../../../core/models/search_result.dart';
import '../../../../core/models/track.dart';
import '../i_music_source.dart';
import '../track_media_item_mapper.dart';

/// Fonte "Internet Archive" (archive.org), usada SÓ pelas 3 seções
/// narrativas da Home ("Minutos de Reflexão", "Contos da Noite",
/// "Poesia Sonora") — mesmo padrão do JamendoSource: é uma fonte
/// ISOLADA, não entra no orquestrador de busca normal
/// (musicSourcesProvider). É chamada direto pelo HomeScreenController
/// e registrada à parte em playbackResolverProvider (ver
/// lib/core/providers/providers.dart) só pra permitir que o player
/// resolva a URL de áudio dessas faixas.
class InternetArchiveSource implements IMusicSource {
  static const _searchUrl = 'https://archive.org/advancedsearch.php';

  @override
  String get sourceId => 'internetarchive';

  @override
  Future<SearchResult> search(
    String query, {
    String? filter,
    String? filterParams,
    int limit = 30,
  }) async {
    // Não faz parte da busca normal do app — só usado pelas seções
    // narrativas da Home via searchNarratedAudio().
    return const SearchResult(sourceId: 'internetarchive');
  }

  @override
  Future<SearchResult> searchContinuation(
    Map<String, dynamic> continuationParams, {
    int limit = 10,
  }) async {
    return const SearchResult(sourceId: 'internetarchive');
  }

  @override
  Future<List<dynamic>> getHomeContent({int limit = 4}) async {
    // A Home usa searchNarratedAudio() diretamente (precisa de
    // query/duração diferentes por seção), então este método genérico
    // da interface não é usado aqui.
    return const [];
  }

  @override
  Future<String> resolveStreamUrl(Track track) async {
    // A URL de áudio já foi resolvida durante a busca (sourceTrackId
    // guarda a URL direta de download do archive.org), então tocar
    // essa faixa não exige nova chamada de rede.
    return track.sourceTrackId;
  }

  /// Busca faixas de áudio no Internet Archive dentro de uma faixa de
  /// duração específica (em segundos). O archive.org não permite
  /// filtrar por duração direto na busca, então isso é feito em 2
  /// passos:
  /// 1) advancedsearch.php: pega candidatos (identifier/title/creator).
  /// 2) metadata/<identifier>: pega os arquivos de cada candidato pra
  ///    descobrir a duração real do áudio e montar a URL de download.
  ///
  /// Processa os candidatos em pequenos lotes (evita disparar dezenas
  /// de requisições simultâneas numa conexão móvel) e para assim que
  /// [resultLimit] faixas válidas forem encontradas.
  Future<List<Track>> searchNarratedAudio({
    required String query,
    required int minSeconds,
    required int maxSeconds,
    int candidateRows = 12,
    int resultLimit = 8,
  }) async {
    final results = <Track>[];

    final searchUri = Uri.parse(_searchUrl).replace(queryParameters: {
      'q': query,
      'fl[]': const ['identifier', 'title', 'creator'],
      'rows': candidateRows.toString(),
      'page': '1',
      'output': 'json',
    });

    final searchResponse =
        await http.get(searchUri).timeout(const Duration(seconds: 8));
    if (searchResponse.statusCode != 200) return results;

    final searchBody = jsonDecode(searchResponse.body) as Map<String, dynamic>;
    final docs =
        (searchBody['response']?['docs'] as List<dynamic>? ?? const []);
    if (docs.isEmpty) return results;

    // Lotes pequenos (3 requisições simultâneas no máximo) pra não
    // competir por banda numa conexão móvel fraca — mesmo motivo pelo
    // qual as 3 seções da Home agora rodam em sequência, nunca juntas.
    const batchSize = 3;
    for (var i = 0; i < docs.length && results.length < resultLimit; i += batchSize) {
      final batch = docs.skip(i).take(batchSize).toList();
      final batchTracks = await Future.wait(batch.map((doc) => _tryBuildTrack(
            doc as Map<String, dynamic>,
            minSeconds: minSeconds,
            maxSeconds: maxSeconds,
          )));
      for (final track in batchTracks) {
        if (track != null) results.add(track);
        if (results.length >= resultLimit) break;
      }
    }

    return results.take(resultLimit).toList();
  }

  Future<Track?> _tryBuildTrack(
    Map<String, dynamic> doc, {
    required int minSeconds,
    required int maxSeconds,
  }) async {
    final identifier = doc['identifier'] as String?;
    if (identifier == null) return null;

    try {
      final metadataUri = Uri.parse('https://archive.org/metadata/$identifier');
      final response =
          await http.get(metadataUri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final files = (body['files'] as List<dynamic>? ?? const []);
      if (files.isEmpty) return null;

      Map<String, dynamic>? audioFile;
      int? durationSeconds;
      for (final f in files) {
        final file = f as Map<String, dynamic>;
        final format = (file['format'] as String? ?? '').toLowerCase();
        if (!format.contains('mp3')) continue;
        final seconds = _parseLength(file['length']);
        if (seconds == null) continue;
        if (seconds < minSeconds || seconds > maxSeconds) continue;
        audioFile = file;
        durationSeconds = seconds;
        break;
      }
      if (audioFile == null || durationSeconds == null) return null;

      final fileName = audioFile['name'] as String;
      final downloadUrl =
          'https://archive.org/download/$identifier/${Uri.encodeComponent(fileName)}';

      final metadata = body['metadata'] as Map<String, dynamic>? ?? const {};
      final title = (metadata['title'] as String?) ??
          (doc['title'] as String?) ??
          identifier;
      final creatorRaw = metadata['creator'] ?? doc['creator'];
      final artist = creatorRaw is List
          ? (creatorRaw.isNotEmpty ? creatorRaw.first.toString() : 'Domínio Público')
          : (creatorRaw?.toString() ?? 'Domínio Público');

      return Track(
        id: 'internetarchive_$identifier',
        title: title,
        artist: artist,
        artworkUrl: '',
        duration: Duration(seconds: durationSeconds),
        sourceId: sourceId,
        sourceTrackId: downloadUrl,
      );
    } catch (_) {
      // Candidato mal formado/sem arquivo de áudio compatível: pula
      // sem derrubar a busca inteira.
      return null;
    }
  }

  int? _parseLength(dynamic raw) {
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty) return null;

    // Já em segundos (ex.: "245.32" ou "245")
    final asDouble = double.tryParse(text);
    if (asDouble != null) return asDouble.round();

    // Formato "MM:SS" ou "H:MM:SS"
    final parts = text.split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    try {
      final nums = parts.map((p) => int.parse(p)).toList();
      if (nums.length == 2) return nums[0] * 60 + nums[1];
      return nums[0] * 3600 + nums[1] * 60 + nums[2];
    } catch (_) {
      return null;
    }
  }

  // --- Cache local (JSON simples em String, seguro pra guardar no Hive
  // sem precisar de TypeAdapter registrado) ---

  static String encodeCachedTracks(List<Track> tracks) {
    return jsonEncode(tracks
        .map((t) => {
              'id': t.id,
              'title': t.title,
              'artist': t.artist,
              'durationSeconds': t.duration?.inSeconds,
              'url': t.sourceTrackId,
            })
        .toList());
  }

  static List<MediaItem> decodeCachedTracks(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) {
      final map = e as Map<String, dynamic>;
      return Track(
        id: map['id'] as String,
        title: map['title'] as String,
        artist: map['artist'] as String,
        artworkUrl: '',
        duration: map['durationSeconds'] != null
            ? Duration(seconds: map['durationSeconds'] as int)
            : null,
        sourceId: 'internetarchive',
        sourceTrackId: map['url'] as String,
      ).toFallbackMediaItem();
    }).toList();
  }
}
