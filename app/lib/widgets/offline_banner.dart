import 'package:flutter/material.dart';

import '../services/snapshot_cache.dart';
import '../theme.dart';
import '../util.dart';

/// A calm note shown when the server cannot be reached. Not red: nothing is broken,
/// the phone keeps trying by itself.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.message, this.showSavedTime = true});

  /// Extra sentence, for example what still works offline.
  final String? message;
  final bool showSavedTime;

  @override
  Widget build(BuildContext context) {
    final saved = SnapshotCache.savedAt;
    final savedText = showSavedTime && saved != null
        ? ' Showing the last saved info from ${agoText(saved.millisecondsSinceEpoch ~/ 1000)}.'
        : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      // Neutral grey on purpose: blue means stairs/exits, red and orange mean danger.
      decoration: cardBox(color: BB.white, border: BB.muted),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_outlined, color: BB.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No connection right now. Retrying by itself.$savedText'
              '${message == null ? '' : ' $message'}',
              style: body(14, color: BB.ink, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
