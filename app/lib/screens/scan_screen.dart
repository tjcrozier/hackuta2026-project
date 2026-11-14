import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/snapshot.dart';
import '../services/api.dart';
import '../services/roomplan.dart';
import '../services/shift.dart';
import '../theme.dart';
import '../widgets/big_button.dart';
import '../widgets/parts_compare.dart';

/// Supervisor scans a floor with LiDAR (Apple RoomPlan), then the scan is uploaded
/// and compared with the floor's last scan. Phones without LiDAR use a saved demo scan.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.floor});

  final int floor;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late final Api _api = context.read<Shift>().api;
  late int _floor = widget.floor;

  bool? _lidar; // null while checking
  String? _busy; // what is happening now, or null when idle
  String? _error;
  Map<String, int>? _before; // the floor's part counts before this scan
  ScanResult? _result;

  @override
  void initState() {
    super.initState();
    RoomPlan.isSupported().then((supported) {
      if (mounted) setState(() => _lidar = supported);
    });
  }

  Future<void> _scanWithLidar() => _run(() async {
        setState(() => _busy = 'Scanning...');
        final files = await RoomPlan.startScan();
        if (files == null) return null; // cancelled
        setState(() => _busy = 'Uploading the scan...');
        return _api.uploadScan(
          floor: _floor,
          model: await File(files.modelPath).readAsBytes(),
          roomJson: await File(files.jsonPath).readAsBytes(),
        );
      });

  /// Fallback: a saved scan of the demo floor that has one new opening.
  Future<void> _useDemoScan() => _run(() async {
        setState(() => _busy = 'Uploading the saved scan...');
        final demoFloor = _floor.clamp(1, 3);
        final data = await rootBundle.load('assets/demo/floor$demoFloor.json');
        return _api.uploadScan(
          floor: _floor,
          model: 'Saved demo scan (no 3D file)'.codeUnits,
          roomJson: data.buffer.asUint8List(),
        );
      });

  Future<void> _run(Future<ScanResult?> Function() scan) async {
    setState(() {
      _error = null;
      _result = null;
    });
    try {
      // Remember the counts before, to show before / after.
      try {
        _before = (await _api.state()).scans[_floor]?.parts;
      } catch (_) {
        _before = null;
      }
      final result = await scan();
      if (mounted) setState(() => _result = result);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'The scan failed.');
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan a floor')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: _result != null ? _resultView(_result!) : _startView(),
          ),
        ),
      );

  List<Widget> _startView() => [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: BB.ink, borderRadius: BorderRadius.circular(20)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FLOOR', style: heading(14, color: BB.line, weight: FontWeight.w500)),
                    Text('$_floor', style: heading(84, color: BB.white)),
                  ],
                ),
              ),
              _stepButton(Icons.remove, 'Floor down',
                  _floor > 1 && _busy == null ? () => setState(() => _floor--) : null),
              const SizedBox(width: 10),
              _stepButton(Icons.add, 'Floor up',
                  _busy == null ? () => setState(() => _floor++) : null),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('How to scan', style: heading(18)),
        const SizedBox(height: 8),
        _tip(Icons.directions_walk_outlined, 'Walk slowly around the floor.'),
        _tip(Icons.center_focus_weak_outlined, 'Point the phone at walls, doors and openings.'),
        _tip(Icons.check_circle_outline, 'Tap Done when the outline looks complete.'),
        const SizedBox(height: 16),
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: cardBox(color: BB.hazardSoft, border: BB.accent),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: BB.accent),
                const SizedBox(width: 10),
                Expanded(child: Text(_error!, style: body(15))),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_lidar == false) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: cardBox(),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: BB.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('This iPhone has no LiDAR. You can use a saved demo scan.',
                      style: body(15, weight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_lidar == true) ...[
          BigButton(
            label: _busy ?? 'Start LiDAR scan',
            icon: Icons.view_in_ar_outlined,
            height: 84,
            busy: _busy != null,
            onPressed: _scanWithLidar,
          ),
          const SizedBox(height: 12),
        ],
        BigButton(
          label: 'Use saved demo scan',
          icon: Icons.folder_open_outlined,
          outlined: _lidar == true,
          color: BB.ink,
          height: _lidar == true ? 56 : 84,
          busy: _lidar != true && _busy != null,
          onPressed: _busy == null ? _useDemoScan : null,
        ),
      ];

  List<Widget> _resultView(ScanResult result) => [
        Text('Floor $_floor scanned', style: heading(26)),
        const SizedBox(height: 12),
        if (result.hazards.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: cardBox(color: BB.safeSoft, border: BB.safe),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: BB.safe, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                      _before == null ? 'First scan of this floor saved.' : 'No new hazards found.',
                      style: heading(18, color: BB.safe)),
                ),
              ],
            ),
          ),
        for (final hazard in result.hazards)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.push('/hazard/${hazard.id}'),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: cardBox(color: BB.hazardSoft, border: BB.accent),
                child: Row(
                  children: [
                    const Icon(Icons.report_problem_outlined, color: BB.accent, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('New hazard',
                              style: body(13, color: BB.accent, weight: FontWeight.w700)),
                          Text(hazard.text, style: body(17, weight: FontWeight.w700)),
                          Text('Supervisor and workers on this floor were texted.',
                              style: body(13, color: BB.muted)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: BB.accent),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        PartsCompare(before: _before, after: result.parts),
        const SizedBox(height: 16),
        BigButton(
          label: 'Done',
          color: BB.ink,
          onPressed: () => context.canPop() ? context.pop() : context.go('/supervisor'),
        ),
        const SizedBox(height: 12),
        BigButton(
          label: 'Scan again',
          outlined: true,
          height: 56,
          onPressed: () => setState(() => _result = null),
        ),
      ];

  Widget _stepButton(IconData icon, String label, VoidCallback? onPressed) => SizedBox(
        width: 60,
        height: 60,
        child: IconButton.filled(
          onPressed: onPressed,
          tooltip: label,
          icon: Icon(icon, size: 28),
          style: IconButton.styleFrom(
            backgroundColor: BB.muted,
            foregroundColor: BB.white,
            disabledBackgroundColor: BB.muted.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );

  Widget _tip(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(icon, color: BB.muted),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: body(16))),
          ],
        ),
      );
}
