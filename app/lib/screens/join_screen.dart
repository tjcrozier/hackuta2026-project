import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../config.dart';
import '../services/shift.dart';
import '../theme.dart';
import '../widgets/big_button.dart';
import '../widgets/shares_box.dart';
import '../widgets/status_pill.dart';

/// Worker joins the site: name, phone, site code, and permissions.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _site = TextEditingController(text: Config.demoMode ? Config.siteCode : '');

  // null = not asked yet, true = allowed, false = not allowed
  bool? _bluetooth;
  bool? _motion;
  bool? _location;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _site.dispose();
    super.dispose();
  }

  // Each "Allow" makes iOS show its permission question by using the feature once.

  Future<void> _allowBluetooth() async {
    bool ok;
    try {
      final state = await FlutterBluePlus.adapterState
          .firstWhere((s) => s != BluetoothAdapterState.unknown)
          .timeout(const Duration(seconds: 20));
      ok = state != BluetoothAdapterState.unauthorized &&
          state != BluetoothAdapterState.unavailable;
    } catch (_) {
      ok = false;
    }
    if (mounted) setState(() => _bluetooth = ok);
  }

  Future<void> _allowMotion() async {
    bool ok;
    try {
      await barometerEventStream().first.timeout(const Duration(seconds: 20));
      ok = true;
    } catch (_) {
      ok = false;
    }
    if (mounted) setState(() => _motion = ok);
  }

  Future<void> _allowLocation() async {
    bool ok;
    try {
      final permission = await Geolocator.requestPermission();
      ok = permission == LocationPermission.whileInUse || permission == LocationPermission.always;
    } catch (_) {
      ok = false;
    }
    if (mounted) setState(() => _location = ok);
  }

  Future<void> _join() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final site = _site.text.trim();
    if (name.isEmpty || phone.isEmpty || site.isEmpty) {
      setState(() => _error = 'Fill in your name, phone number and site code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<Shift>().join(name: name, phone: phone, siteCode: site);
      if (mounted) context.go('/worker');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Join the site')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              _label('Your name'),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'Sajid H.'),
              ),
              _label('Phone number'),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: '+1 555 010 0001'),
              ),
              _label('Site code'),
              TextField(
                controller: _site,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'ARL-0412'),
              ),
              const SizedBox(height: 20),
              if (!kIsWeb) ...[
                Text('Permissions', style: heading(17)),
                const SizedBox(height: 8),
                _PermissionRow(
                  icon: Icons.bluetooth_outlined,
                  title: 'Bluetooth',
                  why: 'Finds your zone. Helps rescuers find you.',
                  state: _bluetooth,
                  onAllow: _allowBluetooth,
                ),
                _PermissionRow(
                  icon: Icons.directions_walk_outlined,
                  title: 'Motion',
                  why: 'Finds your floor. Detects falls.',
                  state: _motion,
                  onAllow: _allowMotion,
                ),
                _PermissionRow(
                  icon: Icons.place_outlined,
                  title: 'Location',
                  why: 'Only while you are on site.',
                  state: _location,
                  onAllow: _allowLocation,
                ),
                const SizedBox(height: 12),
              ],
              const SharesBox(),
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
              BigButton(
                label: 'Join and start shift',
                icon: Icons.login_outlined,
                height: 72,
                busy: _busy,
                onPressed: _join,
              ),
            ],
          ),
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(text, style: body(14, color: BB.muted, weight: FontWeight.w600)),
      );
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.why,
    required this.state,
    required this.onAllow,
  });

  final IconData icon;
  final String title;
  final String why;
  final bool? state;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: cardBox(),
        child: Row(
          children: [
            Icon(icon, color: BB.ink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: body(16, weight: FontWeight.w600)),
                  Text(why, style: body(13, color: BB.muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (state == true)
              const StatusPill('Allowed', kind: PillKind.safe)
            else
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: onAllow,
                  style: FilledButton.styleFrom(
                    backgroundColor: BB.ink,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(state == false ? 'Try again' : 'Allow',
                      style: body(15, color: BB.white, weight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      );
}
