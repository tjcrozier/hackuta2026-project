import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/athena_screen.dart';
import 'screens/athena_live_screen.dart';
import 'screens/beacon_mode_screen.dart';
import 'screens/demo_tools.dart';
import 'screens/fall_check.dart';
import 'screens/finder_screen.dart';
import 'screens/hazard_detail.dart';
import 'screens/join_screen.dart';
import 'screens/mesh_screen.dart';
import 'screens/role_picker.dart';
import 'screens/scan_screen.dart';
import 'screens/supervisor_home.dart';
import 'screens/web/dashboard_screen.dart';
import 'screens/web/rescuer_screen.dart';
import 'screens/worker_home.dart';
import 'services/api.dart';
import 'services/shift.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final shift = Shift(prefs);
  // The app was closed during a shift: carry on where the worker left off.
  final resume = !kIsWeb && shift.resumeShift();
  _router = _buildRouter(initial: resume ? '/worker' : '/');
  runApp(
    ChangeNotifierProvider.value(value: shift, child: const CyclopsApp()),
  );
}

late final GoRouter _router;

GoRouter _buildRouter({required String initial}) => GoRouter(
  initialLocation: initial,
  // In a browser the app opens on the dashboard. The role picker is still at /roles.
  redirect: (_, state) => kIsWeb && state.uri.path == '/' ? '/dashboard' : null,
  routes: [
    GoRoute(path: '/', builder: (_, _) => const RolePicker()),
    GoRoute(path: '/roles', builder: (_, _) => const RolePicker()),
    GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
    // The rescuer link: view-only, no login. (Real version: a secret link that expires.)
    GoRoute(path: '/rescue', builder: (_, _) => const RescuerScreen()),
    GoRoute(path: '/join', builder: (_, _) => const JoinScreen()),
    GoRoute(path: '/worker', builder: (_, _) => const WorkerHome()),
    GoRoute(path: '/beacon', builder: (_, _) => const BeaconModeScreen()),
    GoRoute(path: '/supervisor', builder: (_, _) => const SupervisorHome()),
    GoRoute(
      path: '/scan',
      builder: (_, state) => ScanScreen(
        floor: int.tryParse(state.uri.queryParameters['floor'] ?? '') ?? 1,
      ),
    ),
    GoRoute(
      path: '/hazard/:id',
      builder: (_, state) => HazardDetail(
        hazardId: int.tryParse(state.pathParameters['id']!) ?? 0,
      ),
    ),
    GoRoute(path: '/finder', builder: (_, _) => const FinderScreen()),
    GoRoute(path: '/mesh', builder: (_, _) => const MeshScreen()),
    GoRoute(path: '/demo', builder: (_, _) => const DemoTools()),
    GoRoute(
      path: '/athena',
      builder: (_, state) => AthenaScreen(role: state.uri.queryParameters['role'] ?? 'worker'),
    ),
    // Athena Live (video call). The chat passes its server client; phones fall back to the shift's.
    GoRoute(
      path: '/athena/live',
      builder: (context, state) =>
          AthenaLiveScreen(api: state.extra as Api? ?? context.read<Shift>().api),
    ),
  ],
);

class CyclopsApp extends StatelessWidget {
  const CyclopsApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Cycl0ps',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    routerConfig: _router,
    // The "Did you fall?" screen covers every other screen while a check is open.
    builder: (context, child) => Stack(
      children: [
        ?child,
        if (context.watch<Shift>().check != null) const FallCheck(),
      ],
    ),
  );
}
