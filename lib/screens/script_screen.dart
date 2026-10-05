import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/tts_service.dart';
import 'export_screen.dart';

class ScriptScreen extends StatefulWidget {
  const ScriptScreen({super.key, required this.project});
  final RecapProject project;
  @override
  State<ScriptScreen> createState() => _ScriptScreenState();
}

class _ScriptScreenState extends State<ScriptScreen> {
  final _ctrl = TextEditingController();
  String _voice = burmeseVoices.first.id;
  double _speed = 1.3;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _addLine() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    setState(() {
      widget.project.lines
          .add(ScriptLine(text: t, voiceId: _voice, speed: _speed));
      _ctrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    return Scaffold(
      appBar: AppBar(title: const Text('Script ရေးမယ်')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('အသံ: '),
                    Expanded(
                      child: DropdownButton<String>(
                        value: _voice,
                        isExpanded: true,
                        items: burmeseVoices
                            .map((v) => DropdownMenuItem(
                                value: v.id, child: Text(v.label)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _voice = v!),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('အမြန်: '),
                    Expanded(
                      child: Slider(
                        value: _speed,
                        min: 0.8,
                        max: 1.5,
                        divisions: 14,
                        label: '${_speed.toStringAsFixed(2)}x',
                        onChanged: (v) =>
                            setState(() => _speed = v),
                      ),
                    ),
                    Text('${_speed.toStringAsFixed(2)}x'),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText:
                              'ဇာတ်လမ်း စာကြောင်း ရိုက်ပါ...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle,
                          size: 36),
                      onPressed: _addLine,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: p.lines.length,
              itemBuilder: (_, i) {
                final l = p.lines[i];
                return Dismissible(
                  key: ValueKey('line$i'),
                  direction: DismissDirection.endToStart,
                  background: Container(color: Colors.red),
                  onDismissed: (_) =>
                      setState(() => p.lines.removeAt(i)),
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text(l.text,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${burmeseVoices.firstWhere((v) => v.id == l.voiceId).label} • ${l.speed.toStringAsFixed(2)}x'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: ElevatedButton(
          onPressed: p.lines.isEmpty
              ? null
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            ExportScreen(project: p)),
                  ),
          child: Text('ဆက်လုပ်မယ် (${p.lines.length} ကြောင်း)'),
        ),
      ),
    );
  }
}
