import 'package:meta/meta.dart';

import 'track.dart';

@immutable
class HomeSection {
  final String title;
  final List<Track> tracks;

  const HomeSection({required this.title, required this.tracks});
}
