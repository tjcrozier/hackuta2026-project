import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/mesh_message.dart';
import '../services/mesh.dart';
import '../services/shift.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/big_button.dart';
import '../widgets/status_pill.dart';

/// Offline mesh: phones connected, recent messages with the path they took,
/// and a box to send a short message.
class MeshScreen extends StatefulWidget {
  const MeshScreen({super.key});

  @override
  State<MeshScreen> createState() => _MeshScreenState();
}

class _MeshScreenState extends State<MeshScreen> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _sendText(Shift shift) {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    shift.sendMesh('text', body);
    _text.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final shift = context.watch<Shift>();
    final mesh = shift.mesh;
    // Newest first. Shocks and pings are background traffic, so they are not listed.
    final shown = mesh.messages.reversed.where((m) => m.type != 'shock' && m.type != 'ping').toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Offline mesh')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            _statusCard(shift, mesh),
            if (mesh.error != null) ...[
              const SizedBox(height: 8),
              Text(mesh.error!, style: body(14, color: BB.accent, weight: FontWeight.w600)),
            ],
            if (mesh.running) ...[
              const SizedBox(height: 16),
              Text('Send a message', style: heading(18)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: BigButton(
                      label: 'I need help',
                      icon: Icons.pan_tool_outlined,
                      onPressed: () => shift.sendMesh('help', 'I need help'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: BigButton(
                      label: 'I\'m safe',
                      icon: Icons.check_circle_outline,
                      color: BB.safe,
                      onPressed: () => shift.sendMesh('safe', 'I\'m safe'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      maxLength: 120,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(shift),
                      decoration:
                          const InputDecoration(hintText: 'Short message', counterText: ''),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 64,
                    height: 58,
                    child: IconButton.filled(
                      onPressed: () => _sendText(shift),
                      tooltip: 'Send',
                      icon: const Icon(Icons.send_outlined),
                      style: IconButton.styleFrom(
                        backgroundColor: BB.ink,
                        foregroundColor: BB.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Text('Recent messages', style: heading(18)),
            const SizedBox(height: 8),
            if (shown.isEmpty) Text('No messages yet.', style: body(15, color: BB.muted)),
            for (final message in shown.take(40)) _messageCard(mesh, message),
          ],
        ),
      ),
    );
  }

  Widget _statusCard(Shift shift, Mesh mesh) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: BB.ink, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PHONES CONNECTED',
                          style: heading(13, color: BB.line, weight: FontWeight.w500)),
                      Text(mesh.running ? '${mesh.peers.length}' : '-',
                          style: heading(64, color: BB.white)),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Transform.scale(
                      scale: 1.3,
                      child: Switch(
                        value: shift.offlineMode,
                        activeThumbColor: BB.white,
                        activeTrackColor: BB.safe,
                        onChanged: kIsWeb ? null : shift.setOfflineMode,
                      ),
                    ),
                    Text('Offline mode', style: body(13, color: BB.line)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              kIsWeb
                  ? 'The mesh only works in the iPhone app.'
                  : !mesh.running
                      ? 'The mesh is off. Turn on Offline mode to connect to nearby phones.'
                      : mesh.peers.isEmpty
                          ? 'Looking for nearby phones...'
                          : mesh.peers.keys.map(mesh.nameOf).join(', '),
              style: body(15, color: BB.white),
            ),
            if (mesh.running || mesh.waitingToUpload > 0) ...[
              const Divider(height: 24, color: BB.muted),
              Row(
                children: [
                  Icon(mesh.waitingToUpload == 0 ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                      color: BB.line, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      mesh.waitingToUpload == 0
                          ? 'All messages reached the server.'
                          : '${mesh.waitingToUpload} waiting. They upload when a phone gets internet.',
                      style: body(13, color: BB.line),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );

  Widget _messageCard(Mesh mesh, MeshMessage message) {
    final (pill, text) = switch (message.type) {
      'help' => (const StatusPill('Needs help', kind: PillKind.help), message.body),
      'safe' => (const StatusPill('Safe', kind: PillKind.safe), message.body),
      'rescue' => (
          const StatusPill('Rescue Mode', kind: PillKind.danger),
          'Rescue Mode started: ${message.body}'
        ),
      _ => (const StatusPill('Message', icon: Icons.chat_bubble_outline), message.body),
    };
    final where = message.floor == null
        ? ''
        : 'Floor ${message.floor}, Zone ${message.zone ?? 'unknown'}. ';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(mesh.nameOf(message.originWorkerId), style: heading(17))),
              pill,
            ],
          ),
          const SizedBox(height: 6),
          Text(text, style: body(16, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('$where${agoText(message.createdAt)}', style: body(13, color: BB.muted)),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.alt_route_outlined, size: 16, color: BB.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(pathText(message.path, mesh.nameOf),
                    style: body(13, color: BB.muted, weight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
