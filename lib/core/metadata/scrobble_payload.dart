import 'package:meta/meta.dart';

/// Estrutura pronta para envio ao endpoint track.scrobble do Last.fm,
/// quando/se a submissão autenticada for implementada.
/// Por enquanto é só preparada — não enviada (isso exigiria login do
/// usuário na conta Last.fm dele + assinatura de request com api_secret,
/// que é uma feature separada de "conectar minha conta").
@immutable
class ScrobblePayload {
  final String artist;
  final String track;
  final String? album;
  final int timestampUnixSeconds;

  const ScrobblePayload({
    required this.artist,
    required this.track,
    required this.timestampUnixSeconds,
    this.album,
  });

  Map<String, String> toParams() => {
        'artist': artist,
        'track': track,
        if (album != null) 'album': album!,
        'timestamp': timestampUnixSeconds.toString(),
      };
}
