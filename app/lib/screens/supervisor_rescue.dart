import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/snapshot.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/big_button.dart';
import '../widgets/status_pill.dart';
import 'supervisor_home.dart' show exitFor;

/// Supervisor view while Rescue Mode is on: counts and the list of people.
class SupervisorRescue extends StatelessWidget {
  const SupervisorRescue({
    super.key,
    required this.snapshot,
    required this.busy,
    required this.onStop,
  });

  final Snapshot snapshot;
  final bool busy;
  final VoidCallback onStop;

  /// No answer first, then help, then safe. Higher floors first inside each group.
  static List<WorkerInfo> sorted(List<WorkerInfo> workers) {
    int rank(WorkerInfo w) => switch (w.status) { 'none' => 0, 'help' => 1, _ => 2 };
    return [...workers]..sort((a, b) {
        final byStatus = rank(a).compareTo(rank(b));
        if (byStatus != 0) return byStatus;
        return (b.floor ?? 0).compareTo(a.floor ?? 0);
      });
  }

  @override
  Widget build(BuildContext context) {
    final workers = sorted(snapshot.workers);
    int count(String status) => workers.where((w) => w.status == status).length;

    return Scaffold(
      body: Column(
        children: [
          // Red header
          Container(
            width: double.infinity,
            color: BB.danger,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Icon(Icons.warning_amber_outlined, color: BB.white, size: 32),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Rescue Mode', style: heading(28, color: BB.white)),
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (snapshot.rescueStartedAt != null)
                                'Started ${clockText(snapshot.rescueStartedAt!)} '
                                    '(${elapsedText(snapshot.rescueStartedAt)} ago)',
                              if (snapshot.rescueReason != null) 'Reason: ${snapshot.rescueReason}',
                            ].join('\n'),
                            style: body(14, color: BB.white),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => context.go('/'),
                      tooltip: 'Back to roles',
                      icon: const Icon(Icons.close, color: BB.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _count('${count('none')}', 'No answer', Icons.help_outline,
                          BB.noAnswer, BB.white),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _count('${count('help')}', 'Need help', Icons.pan_tool_outlined,
                          BB.help, BB.helpText),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _count('${count('safe')}', 'Safe', Icons.check_circle_outline,
                          BB.safeSoft, BB.safe),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final worker in workers) _person(worker),
                if (workers.isEmpty)
                  Text('No workers on site.', style: body(16, color: BB.muted)),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: BigButton(
            label: 'Stop Rescue Mode',
            icon: Icons.stop_circle_outlined,
            outlined: true,
            busy: busy,
            onPressed: onStop,
          ),
        ),
      ),
    );
  }

  Widget _count(String value, String label, IconData icon, Color background, Color foreground) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground, size: 22),
            const SizedBox(height: 4),
            Text(value, style: heading(36, color: foreground)),
            Text(label, style: body(13, color: foreground, weight: FontWeight.w600)),
          ],
        ),
      );

  Widget _person(WorkerInfo worker) {
    final pill = switch (worker.status) {
      'safe' => const StatusPill('Safe', kind: PillKind.safe),
      'help' => const StatusPill('Needs help', kind: PillKind.help),
      _ => const StatusPill('No answer', kind: PillKind.noAnswer),
    };
    final where = worker.floor == null
        ? 'Location unknown'
        : 'Floor ${worker.floor}, Zone ${worker.zone ?? '?'}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(worker.name, style: heading(18))),
              pill,
            ],
          ),
          const SizedBox(height: 6),
          Text(where, style: body(15, weight: FontWeight.w600)),
          Text(
            'Last ping ${agoText(worker.lastPing)}'
            '${worker.battery == null ? '' : ', battery ${worker.battery}%'}'
            '${worker.source == 'mesh' ? ', via mesh' : ''}',
            style: body(13, color: BB.muted),
          ),
          if (worker.status != 'safe') ...[
            const SizedBox(height: 6),
            StatusPill(exitFor(worker.zone), kind: PillKind.exit),
          ],
        ],
      ),
    );
  }
}
