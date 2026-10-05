import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/quota_service.dart';
import 'import_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _quota = QuotaService();
  int _remaining = 0;
  final List<RecapProject> _projects = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final r = await _quota.remainingSec();
    if (mounted) setState(() => _remaining = r);
  }

  String _fmt(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recap Maker v3')),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('Export မိနစ် လက်ကျန်'),
              trailing: Text(_fmt(_remaining),
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Recap အသစ် ဖန်တီးမယ်'),
              onPressed: () async {
                final p = await Navigator.push<RecapProject>(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ImportScreen(
                            project: RecapProject(
                              id: DateTime.now()
                                  .millisecondsSinceEpoch
                                  .toString(),
                              name:
                                  'Recap ${DateTime.now().day}/${DateTime.now().month}',
                            ),
                          )),
                );
                if (p != null) {
                  setState(() => _projects.insert(0, p));
                  _refresh();
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _projects.isEmpty
                ? const Center(child: Text('မဖန်တီးရသေးဘူး'))
                : ListView.builder(
                    itemCount: _projects.length,
                    itemBuilder: (_, i) {
                      final p = _projects[i];
                      return ListTile(
                        leading: const Icon(Icons.movie),
                        title: Text(p.name),
                        subtitle: Text(
                            '${p.lines.length} ကြောင်း • ${_fmt(p.videoSeconds.round())}'),
                        trailing: p.outputPath == null
                            ? null
                            : const Icon(Icons.check_circle,
                                color: Colors.green),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
