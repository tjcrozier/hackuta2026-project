import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/snapshot.dart';
import '../services/api.dart';
import '../services/shift.dart';
import '../services/snapshot_cache.dart';
import '../theme.dart';
import '../widgets/big_button.dart';
import '../widgets/offline_banner.dart';
import '../widgets/parts_compare.dart';
import '../widgets/status_pill.dart';

/// One hazard: what changed (before / after), the OSHA topic, who is nearby,
/// and the supervisor's actions.
class HazardDetail extends StatefulWidget {
  const HazardDetail({super.key, required this.hazardId});

  final int hazardId;

  @override
  State<HazardDetail> createState() => _HazardDetailState();
}

class _HazardDetailState extends State<HazardDetail> {
  late final Api _api = context.read<Shift>().api;
  Snapshot? _snapshot;
  String? _error;
  String? _busy; // which button is working

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snapshot = await _api.state();
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (error) {
      final saved = await SnapshotCache.load();
      if (mounted) {
        setState(() {
          _error = '$error';
          _snapshot ??= saved;
          _offline = saved != null;
        });
      }
    }
  }

  bool _offline = false;

  /// Runs one button's server call, then reloads. `done` is the message to show.
  Future<void> _act(String button, Future<String> Function() action) async {
    setState(() => _busy = button);
    try {
      final message = await action();
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    Hazard? hazard;
    for (final h in snapshot?.hazards ?? const <Hazard>[]) {
      if (h.id == widget.hazardId) hazard = h;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Hazard')),
      body: SafeArea(
        child: hazard == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error ?? (snapshot == null ? 'Loading...' : 'This hazard no longer exists.'),
                    textAlign: TextAlign.center,
                    style: body(16, color: BB.muted),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: _content(hazard, snapshot!),
              ),
      ),
    );
  }

  List<Widget> _content(Hazard hazard, Snapshot snapshot) {
    final nearby = snapshot.workers.where((w) => w.floor == hazard.floor).toList();
    final id = hazard.id;
    return [
      if (_offline) ...[const OfflineBanner(), const SizedBox(height: 12)],
      Container(
        padding: const EdgeInsets.all(16),
        decoration: cardBox(
          color: hazard.open ? BB.hazardSoft : BB.white,
          border: hazard.open ? BB.accent : BB.line,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            switch (hazard.status) {
              'fixed' => const StatusPill('Fixed', kind: PillKind.safe),
              'false_alarm' =>
                const StatusPill('False alarm', icon: Icons.do_not_disturb_alt_outlined),
              _ => const StatusPill('Open hazard', kind: PillKind.hazard),
            },
            const SizedBox(height: 10),
            Text(hazard.text, style: heading(24)),
            const SizedBox(height: 6),
            Text('Floor ${hazard.floor}', style: body(15, color: BB.muted)),
          ],
        ),
      ),
      _title('What changed'),
      if (hazard.after != null)
        PartsCompare(before: hazard.before, after: hazard.after!)
      else
        Text('No scan data for this hazard.', style: body(15, color: BB.muted)),
      _title('Safety topic'),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: cardBox(),
        child: Row(
          children: [
            const Icon(Icons.menu_book_outlined, color: BB.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('OSHA topic', style: body(13, color: BB.muted)),
                  Text(hazard.oshaTopic, style: body(16, weight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
      _title('Workers on this floor (${nearby.length})'),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: cardBox(),
        child: nearby.isEmpty
            ? Text('Nobody is on this floor right now.', style: body(15, color: BB.muted))
            : Column(
                children: [
                  for (final worker in nearby)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: BB.ink, borderRadius: BorderRadius.circular(8)),
                            child: Text(worker.zone ?? '?', style: heading(15, color: BB.white)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(worker.name, style: body(16, weight: FontWeight.w600)),
                          ),
                          Text('Zone ${worker.zone ?? 'unknown'}',
                              style: body(13, color: BB.muted)),
                        ],
                      ),
                    ),
                ],
              ),
      ),
      const SizedBox(height: 20),
      BigButton(
        label: 'Warn workers on this floor',
        icon: Icons.campaign_outlined,
        height: 72,
        busy: _busy == 'warn',
        onPressed: _busy == null
            ? () => _act('warn', () async {
                  final sent = await _api.warnFloor(id);
                  return sent == 1 ? '1 worker was texted.' : '$sent workers were texted.';
                })
            : null,
      ),
      const SizedBox(height: 12),
      if (hazard.open) ...[
        BigButton(
          label: 'Mark fixed',
          icon: Icons.check_circle_outline,
          color: BB.safe,
          busy: _busy == 'fixed',
          onPressed: _busy == null
              ? () => _act('fixed', () async {
                    await _api.setHazardStatus(id, 'fixed');
                    return 'Marked fixed.';
                  })
              : null,
        ),
        const SizedBox(height: 12),
        BigButton(
          label: 'False alarm',
          icon: Icons.do_not_disturb_alt_outlined,
          outlined: true,
          height: 56,
          busy: _busy == 'false',
          onPressed: _busy == null
              ? () => _act('false', () async {
                    await _api.setHazardStatus(id, 'false_alarm');
                    return 'Marked as a false alarm.';
                  })
              : null,
        ),
      ] else
        BigButton(
          label: 'Open again',
          icon: Icons.undo_outlined,
          outlined: true,
          height: 56,
          busy: _busy == 'open',
          onPressed: _busy == null
              ? () => _act('open', () async {
                    await _api.setHazardStatus(id, 'open');
                    return 'Hazard is open again.';
                  })
              : null,
        ),
    ];
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(text, style: heading(18)),
      );
}
