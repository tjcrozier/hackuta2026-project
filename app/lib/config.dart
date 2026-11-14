/// Server URL, feature flags and thresholds. Change values here for the demo.
class Config {
  /// Short timers for the demo. Build with --dart-define=DEMO_MODE=false for real timers.
  static const demoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: true);

  /// Default server. Can also be changed inside the app (role picker, "Server").
  /// Build with --dart-define=SERVER_URL=https://xxxx.trycloudflare.com to bake one in.
  static const defaultServerUrl =
      String.fromEnvironment('SERVER_URL', defaultValue: 'http://localhost:8000');

  static const siteName = 'Arlington Site';
  static const siteCode = 'ARL-0412';

  // ---- Feature flags (turn off quickly if something misbehaves in the demo) ----
  static const featureZoneBeacons = true; // Bluetooth zone beacons
  static const featureBarometer = true; // floor from air pressure
  static const featureLocation = true; // lat/lng in pings (only if allowed)
  static const featureKeepAwake = true; // keep the screen on during a shift
  static const featureMotion = true; // fall, shock and no-movement detection
  static const featureMesh = true; // phone-to-phone messages when the internet is down
  static const featureNearby = true; // precise distance with Nearby Interaction (UWB)

  /// iPhone 14 and newer only give a DIRECTION (the arrow) with help from the camera.
  /// ON (the user's choice): the camera runs on the RESCUER's phone while finding, nothing
  /// is recorded or sent, and worker phones never use the camera. Set to false to keep
  /// the camera off; those phones then show the distance without the arrow.
  static const nearbyCameraAssist = true;
  static const featureRescueBeacon = true; // worker phone advertises in Rescue Mode
  static const featureAlarmSound = true; // beep on the "Did you fall?" screen

  // ---- Timers ----
  static const pingNormalSec = demoMode ? 10 : 120;
  static const pingRescueSec = demoMode ? 5 : 60;
  static const fallAnswerSec = demoMode ? 15 : 30;
  static const noMoveMin = demoMode ? 1 : 10;
  static const fallStillSec = 10;

  // ---- Motion thresholds ----
  static const shockG = 3.0;
  static const freefallG = 0.3;
  static const shockGapSec = 10; // send a shock at most once per 10 s

  // ---- Rescue trigger ----
  static const collapsePhones = 3;
  static const collapseWindowSec = 5;

  // ---- Floor from the barometer ----
  static const floorHeightM = 3.5;
  static const hpaPerM = 0.12;

  // ---- Zones ----
  static const zones = ['A', 'B', 'C'];
  static const zoneScanSeconds = 4;
  static const zoneNamePrefix = 'BB-ZONE-';

  /// Nearest stairs for each zone (shown to workers in Rescue Mode).
  static const zoneExits = {'A': 'Stair 1, north side', 'B': 'Stair 1, north side', 'C': 'Stair 2, south side'};
  static const defaultExit = 'Nearest marked stairs';

  // ---- 2D floor map (dashboard and rescuer page) ----
  // There is no exact indoor position. Each worker dot is drawn at the center of their
  // zone, spread out a little. Positions are fractions of the map: (0,0) is the top-left
  // corner (north-west), (1,1) is the bottom-right.
  static const zoneCenters = {'A': (0.19, 0.5), 'B': (0.5, 0.5), 'C': (0.81, 0.5)};

  /// A floor with a different layout can list its own zone centers here.
  static const floorZoneCenters = <int, Map<String, (double, double)>>{};

  /// Where workers with no zone yet are drawn.
  static const unknownZoneCenter = (0.12, 0.86);

  /// Stairs on the map. The names match zoneExits above.
  static const stairs = {'Stair 1': (0.36, 0.1), 'Stair 2': (0.74, 0.9)};

  /// The red button must be held this long. Never a single tap.
  static const holdToStartMs = 2000;
}
