import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/snapshot.dart';
import '../services/api.dart';
import '../services/shift.dart';
import '../theme.dart';
import '../widgets/big_button.dart';

/// Hidden demo tools (long-press the logo). Everything here uses the normal API,
/// so it does exactly what real phones would do.
class DemoTools extends StatefulWidget {
  const DemoTools({super.key});

  @override
  State<DemoTools> createState() => _DemoToolsState();
}

class _DemoToolsState extends State<DemoTools> {
  late final Api _api = context.read<Shift>().api;
  String? _busy; // which button is working
  String? _result; // what the last button did

  /// Runs one tool and shows what happened.
  Future<void> _run(String tool, Future<String> Function() action) async {
    setState(() {
      _busy = tool;
      _result = null;
    });
    try {
      final message = await action();
      if (mounted) setState(() => _result = message);
    } catch (error) {
      if (mounted) setState(() => _result = 'Did not work: $error');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<ScanResult> _uploadSaved(int floor, String file) async {
    final data = await rootBundle.load('assets/demo/$file');
    return _api.uploadScan(
      floor: floor,
      model: 'Saved demo scan (no 3D file)'.codeUnits,
      roomJson: data.buffer.asUint8List(),
    );
  }

  Future<String> _reset() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reset the demo?', style: heading(20)),
        content: Text(
            'Everything goes back to the start: 14 demo workers, yesterday\'s scans, no '
            'hazards, no rescue. Phones that joined will join again by themselves.',
            style: body(15)),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          BigButton(
            label: 'Yes, reset',
            color: BB.ink,
            onPressed: () => Navigator.pop(context, true),
          ),
          const SizedBox(height: 8),
          BigButton(
            label: 'Cancel',
            outlined: true,
            height: 56,
            onPressed: () => Navigator.pop(context, false),
          ),
        ],
      ),
    );
    if (sure != true) return 'Not reset.';
    await _api.demoReset();
    return 'Demo reset.';
  }

  /// Today's scans for floors 1-3, the same as yesterday: no hazards.
  Future<String> _loadScans() async {
    for (final floor in [1, 2, 3]) {
      await _uploadSaved(floor, 'floor$floor-base.json');
    }
    return 'Floors 1-3 now show as scanned today.';
  }

  /// A scan of Floor 3 with a new opening. Uploads a normal scan first, so it works
  /// again and again.
  Future<String> _fakeHazard() async {
    await _uploadSaved(3, 'floor3-base.json');
    final result = await _uploadSaved(3, 'floor3.json');
    return result.hazards.isEmpty
        ? 'Scan saved, but no new hazard was found.'
        : 'Hazard created: ${result.hazards.first.text} Texts were sent.';
  }

  /// Three phones feel a hard impact within the 5-second window.
  Future<String> _fakeCollapse() async {
    final snapshot = await _api.state();
    if (snapshot.rescueActive) return 'Rescue Mode is already on.';
    final workers = snapshot.workers.take(Config.collapsePhones).toList();
    if (workers.length < Config.collapsePhones) {
      return 'Needs ${Config.collapsePhones} workers on site. Reset the demo first.';
    }
    var rescue = false;
    for (final worker in workers) {
      rescue = await _api.event(workerId: worker.id, type: 'shock');
    }
    return rescue
        ? 'Impact on ${workers.length} phones: Rescue Mode started.'
        : 'Shocks sent, but Rescue Mode did not start.';
  }

  Future<String> _stopRescue() async {
    await _api.rescueStop();
    return 'Rescue Mode stopped.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Demo tools')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              Text('For the demo only. These use the normal server calls.',
                  style: body(15, color: BB.muted)),
              Text('Server: ${_api.baseUrl}', style: body(13, color: BB.muted)),
              const SizedBox(height: 16),
              if (_result != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: cardBox(),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: BB.ink),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_result!, style: body(15, weight: FontWeight.w600))),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _tool('reset', 'Reset demo', Icons.restart_alt, BB.ink, _reset),
              _tool('scans', 'Load saved scans (floors 1-3)', Icons.folder_open_outlined, BB.ink,
                  _loadScans),
              _tool('hazard', 'Fake a hazard on Floor 3', Icons.report_problem_outlined, BB.accent,
                  _fakeHazard),
              _tool('collapse', 'Fake a collapse (3 phones)', Icons.warning_amber_outlined,
                  BB.danger, _fakeCollapse),
              _tool('stop', 'Stop Rescue Mode', Icons.stop_circle_outlined, BB.muted, _stopRescue),
            ],
          ),
        ),
      );

  Widget _tool(String id, String label, IconData icon, Color color,
          Future<String> Function() action) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: BigButton(
          label: label,
          icon: icon,
          color: color,
          busy: _busy == id,
          onPressed: _busy == null ? () => _run(id, action) : null,
        ),
      );
}
