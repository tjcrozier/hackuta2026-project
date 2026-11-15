import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Cycl0ps native channels.
    let messenger = engineBridge.applicationRegistrar.messenger()
    RoomPlanBridge.register(messenger: messenger)
    MeshService.shared.register(messenger: messenger)
    NearbyService.shared.register(messenger: messenger)
  }
}
