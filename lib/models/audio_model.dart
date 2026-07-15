enum Codec { mp4a, opus }

class Audio {
  final int itag;
  final Codec audioCodec;
  final int bitrate;
  final int duration;
  final int size;
  final double loudnessDb;
  final String url;

  Audio({
    required this.itag,
    required this.audioCodec,
    required this.bitrate,
    required this.duration,
    required this.loudnessDb,
    required this.url,
    required this.size
  });

  Map<String, dynamic> toJson() => {
    "itag": itag,
    "audioCodec": audioCodec.toString(),
    "bitrate": bitrate,
    "loudnessDb": loudnessDb,
    "url": url,
    "approxDurationMs": duration,
    "size": size
  };

  factory Audio.fromJson(Map<String, dynamic> json) => Audio(
    audioCodec: (json["audioCodec"] as String).contains("mp4a") ? Codec.mp4a : Codec.opus,
    itag: json['itag'],
    duration: json["approxDurationMs"] ?? 0,
    bitrate: json["bitrate"] ?? 0,
    loudnessDb: (json['loudnessDb'] as num?)?.toDouble() ?? 0.0,
    url: json['url'],
    size: json["size"] ?? 0
  );
}
