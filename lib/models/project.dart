// Recap models: project, script lines, timeline segments.

/// One narration line in the script.
class ScriptLine {
  ScriptLine({
    required this.text,
    this.voiceId = 'my-MM-NilarNeural',
    this.speed = 1.3,
  });

  String text;
  String voiceId;
  double speed;

  /// Duration of the generated voiceover in seconds (filled after TTS).
  double audioSeconds = 0;

  Map<String, dynamic> toJson() => {
        'text': text,
        'voiceId': voiceId,
        'speed': speed,
        'audioSeconds': audioSeconds,
      };

  factory ScriptLine.fromJson(Map<String, dynamic> j) => ScriptLine(
        text: j['text'] as String? ?? '',
        voiceId: j['voiceId'] as String? ?? 'my-MM-NilarNeural',
        speed: (j['speed'] as num?)?.toDouble() ?? 1.3,
      )..audioSeconds = (j['audioSeconds'] as num?)?.toDouble() ?? 0;
}

/// One 3-second visual clip mapped to a narration line.
class ClipSegment {
  ClipSegment({
    required this.sourceStartSec,
    required this.durationSec,
    required this.cameraMove,
    required this.scriptIndex,
  });

  /// Start time inside the source movie (seconds).
  double sourceStartSec;

  /// Always 3.0 for main clips.
  double durationSec;

  /// 0=punch-in, 1=zoom-out, 2=pan L->R, 3=pan R->L
  int cameraMove;

  int scriptIndex;

  /// Freeze-frame tail after this clip (seconds, e.g. 0.8).
  double freezeSec = 0.8;
}

/// A recap project.
class RecapProject {
  RecapProject({required this.id, required this.name});

  String id;
  String name;
  String? sourcePath;
  double sourceDurationSec = 0;
  int sourceWidth = 0;
  int sourceHeight = 0;
  List<ScriptLine> lines = [];
  List<ClipSegment> segments = [];
  String? outputPath;
  DateTime createdAt = DateTime.now();

  double get narrationSeconds =>
      lines.fold(0.0, (s, l) => s + l.audioSeconds);

  double get videoSeconds =>
      segments.fold(0.0, (s, c) => s + c.durationSec + c.freezeSec);
}
