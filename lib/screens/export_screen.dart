import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/project.dart';
import '../services/quota_service.dart';
import '../services/timeline_planner.dart';
import '../services/tts_service.dart';
import '../services/video_engine.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key, required this.project});
  final RecapProject project;
  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  double _progress = 0;
  String _stage = 'ပြင်ဆင်နေတယ်...';
  bool _done = false;
  bool _failed = false;
  String? _outPath;
  static const _mediaCh =
      MethodChannel('com.kokoproductions.recap_maker/media');

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<double> _audioSec(String path) async {
    final r = await VideoEngine.probe(path);
    return r['durationSec'] as double;
  }

  Future<void> _start() async {
    final p = widget.project;
    final quota = QuotaService();
    try {
      setState(() => _stage = 'အသံ ထုတ်နေတယ်...');
      // 1. TTS every line
      final tts = TtsService();
      final narrationPaths = <String>[];
      final tempoFix = <bool>[];
      for (var i = 0; i < p.lines.length; i++) {
        final l = p.lines[i];
        final res = await tts.synthesize(
          text: l.text,
          voiceId: l.voiceId,
          speed: l.speed,
          outName: '${p.id}_line$i',
        );
        l.audioSeconds = await _audioSec(res.path);
        // If TTS baked the speed in (Edge), measure at baked speed already.
        // If not (gTTS fallback), atempo will fix it in render.
        narrationPaths.add(res.path);
        tempoFix.add(!res.speedBakedIn);
        if (mounted) {
          setState(() {
            _progress = 0.05 + 0.15 * (i + 1) / p.lines.length;
            _stage = 'အသံ ${i + 1}/${p.lines.length}';
          });
        }
      }
      // 2. Plan timeline
      setState(() => _stage = 'Clip တွေ စီစဉ်နေတယ်...');
      p.segments = TimelinePlanner.plan(
        sourceDuration: p.sourceDurationSec,
        lineDurations: p.lines.map((l) => l.audioSeconds).toList(),
      );
      final needSec =
          (p.videoSeconds).ceil() + 30; // safety margin
      // 3. Quota check
      final ok = await quota.consume(needSec);
      if (!ok) {
        throw Exception(
            'Export မိနစ် မလောက်ဘူး — ကြော်ငြာကြည့်ပြီး ဖြည့်ပါ');
      }
      // 4. Render
      final out = await VideoEngine.render(
        project: p,
        narrationPaths: narrationPaths,
        tempoFix: tempoFix,
        onProgress: (prog, stage) {
          if (mounted) {
            setState(() {
              _progress = 0.2 + 0.8 * prog;
              _stage = stage.isEmpty ? 'Render လုပ်နေတယ်...' : stage;
            });
          }
        },
      );
      // 5. Save to gallery
      setState(() => _stage = 'Gallery ထဲ သိမ်းနေတယ်...');
      final saved = await _mediaCh.invokeMethod<String>(
          'saveToGallery', {'path': out});
      p.outputPath = saved;
      if (mounted) {
        setState(() {
          _done = true;
          _progress = 1;
          _stage = 'ပြီးပြီ!';
          _outPath = saved;
        });
      }
      if (mounted) Navigator.pop(context, p);
    } catch (e) {
      await quota.refund(0); // consumed amount unknown here; best-effort
      if (mounted) {
        setState(() {
          _failed = true;
          _stage = 'မှားသွားတယ်: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export လုပ်နေတယ်')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_done && !_failed) ...[
                CircularProgressIndicator(value: _progress),
                const SizedBox(height: 16),
                Text('${(_progress * 100).toStringAsFixed(0)}%'),
              ] else if (_done) ...[
                const Icon(Icons.check_circle,
                    color: Colors.green, size: 72),
                if (_outPath != null) Text(_outPath!),
              ] else ...[
                const Icon(Icons.error, color: Colors.red, size: 72),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ပြန်သွားမယ်'),
                ),
              ],
              const SizedBox(height: 12),
              Text(_stage, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
