import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/video_engine.dart';
import 'script_screen.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.project});
  final RecapProject project;
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool _busy = false;
  String? _err;

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.video,
      );
      if (files.isEmpty || files.single.path == null) {
        setState(() => _busy = false);
        return;
      }
      final path = files.single.path!;
      final info = await VideoEngine.probe(path);
      widget.project
        ..sourcePath = path
        ..sourceDurationSec = info['durationSec'] as double
        ..sourceWidth = info['width'] as int
        ..sourceHeight = info['height'] as int;
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ScriptScreen(project: widget.project)),
      );
    } catch (e) {
      setState(() => _err = 'Video ဖတ်မရဘူး: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video ရွေးမယ်')),
      body: Center(
        child: _busy
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.video_library,
                      size: 72, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('ဖုန်းထဲက movie/video ဖိုင် ရွေးပါ'),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('ဖိုင် ရွေးမယ်'),
                    onPressed: _pick,
                  ),
                  if (_err != null) ...[
                    const SizedBox(height: 12),
                    Text(_err!,
                        style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
      ),
    );
  }
}
