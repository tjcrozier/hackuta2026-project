/// A message that hops from phone to phone when the internet is down
/// (see BUILD_PLAN.md, "Mesh message format").
class MeshMessage {
  MeshMessage({
    required this.msgId,
    required this.originWorkerId,
    required this.type,
    this.body = '',
    this.zone,
    this.floor,
    this.battery,
    required this.createdAt,
    this.ttl = startTtl,
    this.path = const [],
  });

  /// A new message can make this many hops.
  static const startTtl = 5;

  final String msgId;
  final String originWorkerId;
  final String type; // help, safe, ping, text, shock, rescue
  final String body;
  final String? zone;
  final int? floor;
  final int? battery;
  final int createdAt; // seconds since 1970
  final int ttl; // hops left
  final List<String> path; // ids of the phones it passed through, origin first

  /// The copy a phone keeps and passes on: its own id added to the path, one hop used.
  MeshMessage hop(String selfId) => MeshMessage(
        msgId: msgId,
        originWorkerId: originWorkerId,
        type: type,
        body: body,
        zone: zone,
        floor: floor,
        battery: battery,
        createdAt: createdAt,
        ttl: ttl - 1,
        path: [...path, selfId],
      );

  Map<String, dynamic> toJson() => {
        'msg_id': msgId,
        'origin_worker_id': originWorkerId,
        'type': type,
        'body': body,
        'zone': zone,
        'floor': floor,
        'battery': battery,
        'created_at': createdAt,
        'ttl': ttl,
        'path': path,
      };

  factory MeshMessage.fromJson(Map<String, dynamic> json) => MeshMessage(
        msgId: json['msg_id'] as String,
        originWorkerId: (json['origin_worker_id'] as String?) ?? '',
        type: (json['type'] as String?) ?? 'text',
        body: (json['body'] as String?) ?? '',
        zone: json['zone'] as String?,
        floor: (json['floor'] as num?)?.toInt(),
        battery: (json['battery'] as num?)?.toInt(),
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
        ttl: (json['ttl'] as num?)?.toInt() ?? 0,
        path: ((json['path'] as List?) ?? const []).map((id) => '$id').toList(),
      );
}
