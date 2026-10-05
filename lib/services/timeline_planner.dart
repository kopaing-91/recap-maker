// Timeline planner: map each narration line to unique 3-second clips.
// Rules (locked with Ko):
// - every source clip is exactly 3 seconds
// - no clip reused within one video
// - chronological order, spread across the movie
// - camera moves cycle: punch-in, zoom-out, pan L->R, pan R->L
// - every clip gets a freeze-frame zoom tail (0.8s)

import 'dart:math';
import '../models/project.dart';

class TimelinePlanner {
  static const double clipSec = 3.0;
  static const double freezeSec = 0.8;

  /// [lineDurations] = voiceover seconds per script line (after TTS).
  static List<ClipSegment> plan({
    required double sourceDuration,
    required List<double> lineDurations,
  }) {
    final rnd = Random(42); // deterministic spread
    final maxStart = (sourceDuration - clipSec - 1.0).clamp(1.0, 1e9);
    final used = <int>[]; // used start-second buckets
    final segments = <ClipSegment>[];
    var move = 0;

    // Spread narration across the movie: line i targets fraction i/n.
    final n = lineDurations.length;
    for (var i = 0; i < n; i++) {
      final needClips = max(1, (lineDurations[i] / clipSec).ceil());
      for (var k = 0; k < needClips; k++) {
        final frac = n <= 1 ? 0.5 : (i + (k / needClips)) / n;
        var start = (frac * maxStart);
        // jitter + find unused bucket
        for (var attempt = 0; attempt < 50; attempt++) {
          final cand =
              (start + (rnd.nextDouble() - 0.5) * maxStart * 0.06)
                  .clamp(0.0, maxStart);
          final bucket = cand.floor();
          if (!used.contains(bucket)) {
            used.add(bucket);
            segments.add(ClipSegment(
              sourceStartSec: cand,
              durationSec: clipSec,
              cameraMove: move % 4,
              scriptIndex: i,
            )..freezeSec = freezeSec);
            move++;
            break;
          }
          start += 3.5;
          if (start > maxStart) start = 0;
        }
      }
    }
    return segments;
  }
}
