import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../services/shift.dart';
import '../theme.dart';

/// Rescue Mode on a worker's phone: the whole screen is dark red with two huge buttons.
class WorkerRescue extends StatelessWidget {
  const WorkerRescue({super.key});

  @override
  Widget build(BuildContext context) {
    final shift = context.watch<Shift>();
    final status = shift.rescueStatus;
    return Scaffold(
      backgroundColor: BB.noAnswer,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_outlined, color: BB.white, size: 34),
                const SizedBox(width: 10),
                Expanded(child: Text('Emergency on site', style: heading(28, color: BB.white))),
                IconButton(
                  onPressed: () => context.go('/'),
                  tooltip: 'Back to roles',
                  icon: const Icon(Icons.close, color: BB.white),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              status == 'none' ? 'Are you OK? Tap one.' : 'Your answer was recorded.',
              style: body(18, color: BB.white),
            ),
            const SizedBox(height: 16),
            if (status == 'none') ...[
              _answerButton(
                label: 'I\'m safe',
                icon: Icons.check_circle_outline,
                background: BB.white,
                foreground: BB.ink,
                onPressed: () => shift.answerRescue('safe'),
              ),
              const SizedBox(height: 14),
              _answerButton(
                label: 'I need help',
                icon: Icons.pan_tool_outlined,
                background: BB.help,
                foreground: BB.helpText,
                onPressed: () => shift.answerRescue('help'),
              ),
            ] else ...[
              _answered(shift, status),
            ],
            const SizedBox(height: 18),
            _info(Icons.place_outlined, 'Your last spot',
                'Floor ${shift.floor.floor}, Zone ${shift.zone ?? 'unknown'}'),
            _info(Icons.stairs_outlined, 'Nearest exit',
                Config.zoneExits[shift.zone] ?? Config.defaultExit),
            _info(Icons.my_location_outlined, 'Location',
                'Sent every ${Config.pingRescueSec} seconds'),
            _info(
                Icons.battery_std_outlined,
                'Battery',
                shift.battery == null
                    ? 'Keep this screen open'
                    : '${shift.battery}%. Keep this screen open'),
            if (shift.beaconOn)
              _info(Icons.bluetooth_searching_outlined, 'Bluetooth signal on',
                  'Rescuers can find this phone'),
            if (shift.mesh.running)
              InkWell(
                onTap: () => context.push('/mesh'),
                child: _info(Icons.hub_outlined, 'Offline mesh (tap to open)',
                    '${shift.mesh.peers.length} phones connected'),
              ),
            const SizedBox(height: 8),
            Text(
              'To save battery: lower the screen brightness and close other apps. '
              'Do not close Black Box.',
              style: body(14, color: BB.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _answerButton({
    required String label,
    required IconData icon,
    required Color background,
    required Color foreground,
    required VoidCallback onPressed,
  }) =>
      SizedBox(
        height: 132,
        width: double.infinity,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 44),
              const SizedBox(width: 14),
              Flexible(child: FittedBox(child: Text(label, style: heading(40, color: foreground)))),
            ],
          ),
        ),
      );

  /// After answering: a big confirmation, plus a way to change the answer.
  Widget _answered(Shift shift, String status) {
    final safe = status == 'safe';
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: safe ? BB.white : BB.help,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              Icon(safe ? Icons.check_circle_outline : Icons.pan_tool_outlined,
                  size: 56, color: safe ? BB.safe : BB.helpText),
              const SizedBox(height: 8),
              Text(safe ? 'Marked safe' : 'Help is coming',
                  style: heading(36, color: safe ? BB.ink : BB.helpText)),
              const SizedBox(height: 6),
              Text(
                !shift.answerSent
                    ? 'No connection. Sending again...'
                    : safe
                        ? 'Go to the nearest exit if you can.'
                        : 'Stay where you are if it is safe. Rescuers can see your last spot.',
                textAlign: TextAlign.center,
                style: body(16, color: safe ? BB.muted : BB.helpText),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 64,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => shift.answerRescue(safe ? 'help' : 'safe'),
            icon: Icon(safe ? Icons.pan_tool_outlined : Icons.check_circle_outline),
            label: Text(safe ? 'Change to: I need help' : 'Change to: I\'m safe',
                style: heading(18, color: BB.white)),
            style: OutlinedButton.styleFrom(
              foregroundColor: BB.white,
              side: const BorderSide(color: BB.white, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _info(IconData icon, String label, String value) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: BB.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: BB.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: body(13, color: BB.white)),
                  Text(value, style: body(17, color: BB.white, weight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      );
}
