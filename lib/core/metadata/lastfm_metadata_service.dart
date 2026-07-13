import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'i_metadata_provider.dart';
import 'scrobble_payload.dart';

/// apiKey vem de --dart-define (Secret do GitHub Actions).
/// Só usa endpoints de LEITURA (track.getInfo, track.getSimilar) —
/// não requer login do usuário. Scrobble fica só preparado (ver
/// prepareScrobble), submissão autenticada é feature futura.
class LastFmMetadataService implements IMetadataProvider {
  final String apiKey;
  static const _baseUrl = 'https://ws.audioscrobbler.com/2.0/';
  static const _timeout = Duration(seconds: 3);

  LastFmMetadataService({required this.apiKey});

  @override
  Future<Track> enrich(Track track) async {
    if (apiKey.isEmpty) return track;

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'method': 'track.getInfo',
      'api_key': apiKey,
      'artist': track.artist,
      'track': track.title,
      'format': 'json',
      'autocorrect': '1', // Last.fm corrige erros comuns de título/artista
    });

    try {
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return track;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final info = body['track'] as Map<String, dynamic>?;
      if (info == null) return track; // não encontrado: mantém original

      final cleanTitle = info['name'] as String? ?? track.title;
      final cleanArtist =
          (info['artist'] as Map<String, dynamic>?)?['name'] as String? ??
              track.artist;
      final artwork = _bestImage(info['album'] as Map<String, dynamic>?) ??
          track.artworkUrl;

      return track.copyWith(
        title: cleanTitle,
        artist: cleanArtist,
        artworkUrl: artwork,
        isEnriched: true,
      );
    } catch (_) {
      // Last.fm fora do ar / timeout: usuário nunca percebe,
      // só não recebe o polimento extra nesta faixa.
      return track;
    }
  }

  @override
  Future<List<String>> findSimilar(Track track, {int limit = 5}) async {
    if (apiKey.isEmpty) return [];

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'method': 'track.getSimilar',
      'api_key': apiKey,
      'artist': track.artist,
      'track': track.title,
      'format': 'json',
      'limit': limit.toString(),
      'autocorrect': '1',
    });

    try {
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return [];

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final matches =
          (body['similartracks'] as Map<String, dynamic>?)?['track']
              as List<dynamic>?;
      if (matches == null) return [];

      return matches
          .map((m) => (m as Map<String, dynamic>)['name'] as String? ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  ScrobblePayload prepareScrobble(Track track, {required DateTime playedAt}) {
    return ScrobblePayload(
      artist: track.artist,
      track: track.title,
      timestampUnixSeconds: playedAt.millisecondsSinceEpoch ~/ 1000,
    );
  }

  String? _bestImage(Map<String, dynamic>? album) {
    final images = album?['image'] as List<dynamic>?;
    if (images == null || images.isEmpty) return null;
    // Last.fm retorna do menor pro maior ("small" -> "extralarge");
    // o último costuma ser o de melhor qualidade disponível.
    final url = images.last['#text'] as String?;
    return (url == null || url.isEmpty) ? null : url;
  }
}
