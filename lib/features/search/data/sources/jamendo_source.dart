import '../../../../core/models/track.dart';
import '../i_music_source.dart';

/// Esqueleto — aguardando API key do Jamendo (você me avisa quando tiver).
class JamendoSource implements IMusicSource {
  final String clientId;
  JamendoSource({required this.clientId});

  @override
  String get sourceId => 'jamendo';

  @override
  Future<List<Track>> search(String query) async {
    // TODO: chamada HTTP para https://api.jamendo.com/v3.0/tracks
    // mapear resultado para Track(sourceId: 'jamendo', ...)
    return [];
  }

  @override
  Future<String> resolveStreamUrl(Track track) async {
    // Jamendo já retorna audio URL direto no search — não precisa
    // de segunda chamada, diferente do YouTube.
    throw UnimplementedError('Aguardando API key');
  }
}
