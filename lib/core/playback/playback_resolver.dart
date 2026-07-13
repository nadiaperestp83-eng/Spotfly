import '../models/track.dart';

abstract class IPlaybackResolver {
  Future<String> resolve(Track track);
}
