import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/snapshot.dart';
import '../services/api.dart';
import '../services/live_socket.dart';
import '../services/shift.dart';
import '../services/snapshot_cache.dart';

/// What a live screen gets: the newest snapshot, the connection state, and the API.
class Live {
  Live({
    required this.api,
    required this.snapshot,
    required this.connected,
    required this.offline,
    required this.refresh,
  });
  final Api api;
  final Snapshot? snapshot;
  final bool connected;
  final bool offline; // no connection for a few seconds: show the offline banner
  final Future<void> Function() refresh;
}

/// Keeps a WS /live connection open and rebuilds when a new snapshot arrives.
/// Also rebuilds once per second so "12 s ago" texts stay fresh.
class LiveBuilder extends StatefulWidget {
  const LiveBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, Live live) builder;

  @override
  State<LiveBuilder> createState() => _LiveBuilderState();
}

class _LiveBuilderState extends State<LiveBuilder> {
  late final Api _api = context.read<Shift>().api;
  LiveSocket? _socket;
  Timer? _clock;
  Snapshot? _snapshot;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _socket = LiveSocket(
      baseUrl: _api.baseUrl,
      onSnapshot: (snapshot) {
        if (mounted) setState(() => _snapshot = snapshot);
      },
      onConnected: (connected) {
        if (mounted) setState(() => _connected = connected);
      },
    )..connect();
    // Show the last saved data right away; live data replaces it when it arrives.
    SnapshotCache.load().then((saved) {
      if (mounted && _snapshot == null && saved != null) setState(() => _snapshot = saved);
    });
    _refresh();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _socket?.close();
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final snapshot = await _api.state();
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (_) {}
  }

  /// "No connection" only after a moment, so the banner does not flash on every page load.
  bool get _offline => !_connected && DateTime.now().difference(_openedAt).inSeconds >= 4;
  final _openedAt = DateTime.now();

  @override
  Widget build(BuildContext context) => widget.builder(
        context,
        Live(
            api: _api,
            snapshot: _snapshot,
            connected: _connected,
            offline: _offline,
            refresh: _refresh),
      );
}
