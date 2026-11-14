import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/snapshot.dart';
import 'snapshot_cache.dart';

/// Listens to WS /live and reconnects every 3 seconds when the link drops.
class LiveSocket {
  LiveSocket({required this.baseUrl, required this.onSnapshot, this.onConnected});

  final String baseUrl; // http(s)://host:port
  final void Function(Snapshot snapshot) onSnapshot;
  final void Function(bool connected)? onConnected;

  static const retryDelay = Duration(seconds: 3);

  WebSocketChannel? _channel;
  Timer? _retry;
  bool _closed = false;

  /// http://host -> ws://host/live, https://host -> wss://host/live
  static Uri liveUri(String baseUrl) => Uri.parse('${baseUrl.replaceFirst('http', 'ws')}/live');

  void connect() {
    if (_closed) return;
    try {
      final channel = WebSocketChannel.connect(liveUri(baseUrl));
      _channel = channel;
      channel.ready.then((_) => onConnected?.call(true)).catchError((_) {});
      channel.stream.listen(
        (data) {
          try {
            final json = Map<String, dynamic>.from(jsonDecode(data as String) as Map);
            onSnapshot(Snapshot.fromJson(json));
            SnapshotCache.save(json);
          } catch (_) {
            // Ignore a message we cannot read; the next one replaces it anyway.
          }
        },
        onDone: _lost,
        onError: (_) => _lost(),
        cancelOnError: true,
      );
    } catch (_) {
      _lost();
    }
  }

  void _lost() {
    if (_closed) return;
    onConnected?.call(false);
    _retry?.cancel();
    _retry = Timer(retryDelay, connect);
  }

  void close() {
    _closed = true;
    _retry?.cancel();
    _channel?.sink.close();
  }
}
