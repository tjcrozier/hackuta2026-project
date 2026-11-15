import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/shift.dart';
import '../theme.dart';
import '../widgets/logo.dart';

/// First screen: choose what this phone does.
class RolePicker extends StatelessWidget {
  const RolePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final shift = context.watch<Shift>();
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 12),
            Row(
              children: [
                const Logo(size: 44),
                const SizedBox(width: 12),
                Text('Cycl0ps', semanticsLabel: 'Cyclops', style: heading(30)),
              ],
            ),
            const SizedBox(height: 8),
            Text('Know who is inside.', style: body(16, color: BB.muted)),
            const SizedBox(height: 24),
            Text('What is this phone for?', style: heading(20)),
            const SizedBox(height: 12),
            _RoleCard(
              icon: Icons.engineering_outlined,
              title: 'Worker',
              subtitle: shift.joined ? 'Joined as ${shift.name}' : 'Join the site and start a shift',
              onTap: () => context.push(shift.joined ? '/worker' : '/join'),
            ),
            _RoleCard(
              icon: Icons.assignment_ind_outlined,
              title: 'Supervisor',
              subtitle: 'Scan floors, see the crew, start Rescue Mode',
              onTap: () => context.push('/supervisor'),
            ),
            _RoleCard(
              icon: Icons.radar_outlined,
              title: 'Rescuer finder',
              subtitle: 'Find a missing worker\'s phone',
              onTap: () => context.push('/finder'),
            ),
            _RoleCard(
              icon: Icons.sensors_outlined,
              title: 'Zone beacon',
              subtitle: 'Leave this device in a zone as a marker',
              onTap: () => context.push('/beacon'),
            ),
            _RoleCard(
              icon: Icons.hub_outlined,
              title: 'Offline mesh',
              subtitle: 'Send messages phone to phone with no internet',
              onTap: () => context.push('/mesh'),
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _editServer(context, shift),
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: cardBox(color: BB.ground),
                child: Row(
                  children: [
                    const Icon(Icons.dns_outlined, color: BB.muted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Server', style: body(13, color: BB.muted)),
                          Text(shift.serverUrl,
                              style: body(15, weight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Text('Change', style: body(15, color: BB.accent, weight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editServer(BuildContext context, Shift shift) async {
    final controller = TextEditingController(text: shift.serverUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Server address', style: heading(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The laptop address or the cloudflared link.', style: body(14, color: BB.muted)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: 'http://192.168.1.20:8000'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (url != null) await shift.setServerUrl(url);
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: BB.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: BB.line),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 84),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(icon, size: 34, color: BB.ink),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(title, style: heading(20)),
                        const SizedBox(height: 4),
                        Text(subtitle, style: body(14, color: BB.muted)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: BB.muted),
                ],
              ),
            ),
          ),
        ),
      );
}
