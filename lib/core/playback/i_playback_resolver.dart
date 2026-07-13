import '../models/track.dart';

/// Traduz um Track (metadado) em uma URL de áudio reproduzível.
/// É a ÚNICA peça que sabe que fontes existem — o Player não sabe.
abstract class IPlaybackResolver {
  Future<String> resolve(Track track);
}
