import 'package:flutter/material.dart';

import '../theme.dart';

/// "What your phone shares" box. Shown on the join screen and the worker home.
class SharesBox extends StatelessWidget {
  const SharesBox({super.key, this.zone, this.floor, this.battery});

  final String? zone;
  final int? floor;
  final int? battery;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: cardBox(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What your phone shares', style: heading(17)),
            const SizedBox(height: 10),
            _row(Icons.grid_view_outlined, 'Zone', zone),
            _row(Icons.layers_outlined, 'Floor', floor?.toString()),
            _row(Icons.battery_std_outlined, 'Battery', battery == null ? null : '$battery%'),
            const Divider(height: 24, color: BB.line),
            Row(
              children: [
                const Icon(Icons.block_outlined, size: 20, color: BB.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Never: camera, microphone, messages',
                      style: body(14, weight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Only between Start shift and End shift.', style: body(13, color: BB.muted)),
          ],
        ),
      );

  Widget _row(IconData icon, String label, String? value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: BB.muted),
            const SizedBox(width: 10),
            Text(label, style: body(15)),
            const Spacer(),
            if (value != null) Text(value, style: body(15, weight: FontWeight.w600)),
          ],
        ),
      );
}
