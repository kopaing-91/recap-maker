// Bridge to the native Kotlin video engine (ffmpeg-kit + MediaCodec).

import 'dart:async';
import 'package:flutter/services.dart';
import '../models/project.dart';

class VideoEngine {
  static const _ch = MethodChannel('com.kokoproductions.recap_maker/video');

  /// Probe a video file. Returns durationSec, width, height.
  static Future<Map<String, dynamic>> probe(String path) async {
    final r = await _ch.invokeMethod<Map<dynamic, dynamic>>(
        'probe', {'path': path});
    return {
      'durationSec': (r!['durationSec'] as num).toDouble(),
      'width': r['width'] as int,
      'height': r['height'] as int,
    };
  }

  /// Render the full recap. Emits progress 0..1 via [onProgress].
  /// Returns the output file path.
  /// [tempoFix] marks narration files whose speed was NOT baked in by TTS
  /// (gTTS fallback) so the engine applies atempo.
  static Future<String> render({
    required RecapProject project,
    required List<String> narrationPaths,
    required List<bool> tempoFix,
    required void Function(double progress, String stage) onProgress,
  }) async {
    final sub = _progressStream().listen((e) {
      onProgress((e['progress'] as num).toDouble(),
          e['stage'] as String? ?? '');
    });
    try {
      final out = await _ch.invokeMethod<String>('render', {
        'sourcePath': project.sourcePath,
        'segments': project.segments
            .map((s) => {
                  'start': s.sourceStartSec,
                  'dur': s.durationSec,
                  'move': s.cameraMove,
                  'freeze': s.freezeSec,
                  'scriptIndex': s.scriptIndex,
                })
            .toList(),
        'narrationPaths': narrationPaths,
        'tempoFix': tempoFix,
        'scriptTexts':
            project.lines.map((l) => l.text).toList(),
        'speeds': project.lines.map((l) => l.speed).toList(),
        'workDir': project.id,
      });
      return out!;
    } finally {
      await sub.cancel();
    }
  }

  static Stream<Map<String, dynamic>> _progressStream() {
    return const EventChannel('com.kokoproductions.recap_maker/videoProgress')
        .receiveBroadcastStream()
        .map((e) => Map<String, dynamic>.from(e as Map));
  }

  static Future<void> cancel() => _ch.invokeMethod('cancel');
}
