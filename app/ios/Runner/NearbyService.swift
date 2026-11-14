import Flutter
import NearbyInteraction

/// Precise finder with Apple Nearby Interaction (ultra-wideband, iPhone 11 and newer).
/// Two phones swap "discovery tokens" (over the mesh), then each phone measures the
/// distance, and where supported the direction, to the other.
///
/// MethodChannel "blackbox/nearby":
///   capabilities                 -> {distance, direction, cameraAssist} (Bools)
///   myToken(peerId)              -> this phone's token for that peer (base64), or nil
///   setPeerToken(peerId, token, cameraAssist)  start measuring
///   stop(peerId?)                stop one peer, or all
/// EventChannel "blackbox/nearby/events" sends maps:
///   {peerId, distanceM?, directionX?, directionY?, directionZ?, horizontalAngle?}
///   {peerId, lost: true}
final class NearbyService: NSObject, FlutterStreamHandler, NISessionDelegate {
  static let shared = NearbyService()

  private var sessions: [String: NISession] = [:]  // one session per peer
  private var configs: [String: NINearbyPeerConfiguration] = [:]
  private var eventSink: FlutterEventSink?

  func register(messenger: FlutterBinaryMessenger) {
    let methods = FlutterMethodChannel(name: "blackbox/nearby", binaryMessenger: messenger)
    methods.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      let args = call.arguments as? [String: Any] ?? [:]
      let peerId = args["peerId"] as? String
      switch call.method {
      case "capabilities":
        let caps = NISession.deviceCapabilities
        result([
          "distance": caps.supportsPreciseDistanceMeasurement,
          "direction": caps.supportsDirectionMeasurement,
          "cameraAssist": caps.supportsCameraAssistance,
        ])
      case "myToken":
        result(peerId.flatMap { self.myToken(peerId: $0) })
      case "setPeerToken":
        if let peerId = peerId, let token = args["token"] as? String {
          self.setPeerToken(
            peerId: peerId, token: token, cameraAssist: args["cameraAssist"] as? Bool ?? false)
        }
        result(nil)
      case "stop":
        self.stop(peerId: peerId)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    FlutterEventChannel(name: "blackbox/nearby/events", binaryMessenger: messenger)
      .setStreamHandler(self)
  }

  private func session(for peerId: String) -> NISession {
    if let existing = sessions[peerId] { return existing }
    let created = NISession()
    created.delegate = self
    sessions[peerId] = created
    return created
  }

  private func peerId(of session: NISession) -> String? {
    return sessions.first { $0.value === session }?.key
  }

  /// This phone's token for one peer, as base64 text that can travel over the mesh.
  private func myToken(peerId: String) -> String? {
    guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement,
      let token = session(for: peerId).discoveryToken,
      let data = try? NSKeyedArchiver.archivedData(
        withRootObject: token, requiringSecureCoding: true)
    else { return nil }
    return data.base64EncodedString()
  }

  /// The other phone's token arrived: start measuring.
  private func setPeerToken(peerId: String, token: String, cameraAssist: Bool) {
    guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement,
      let data = Data(base64Encoded: token),
      let peerToken = try? NSKeyedUnarchiver.unarchivedObject(
        ofClass: NIDiscoveryToken.self, from: data)
    else { return }
    let config = NINearbyPeerConfiguration(peerToken: peerToken)
    // Newer iPhones only give a direction with help from the camera. Off unless asked for.
    if cameraAssist && NISession.deviceCapabilities.supportsCameraAssistance {
      config.isCameraAssistanceEnabled = true
    }
    configs[peerId] = config
    session(for: peerId).run(config)
  }

  private func stop(peerId: String?) {
    let ids = peerId.map { [$0] } ?? Array(sessions.keys)
    for id in ids {
      sessions[id]?.invalidate()
      sessions[id] = nil
      configs[id] = nil
    }
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { self.eventSink?(event) }
  }

  // MARK: NISessionDelegate

  func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
    guard let id = peerId(of: session), let object = nearbyObjects.first else { return }
    var event: [String: Any] = ["peerId": id]
    if let distance = object.distance { event["distanceM"] = Double(distance) }
    if let direction = object.direction {
      event["directionX"] = Double(direction.x)
      event["directionY"] = Double(direction.y)
      event["directionZ"] = Double(direction.z)
    }
    if let angle = object.horizontalAngle { event["horizontalAngle"] = Double(angle) }
    emit(event)
  }

  func session(
    _ session: NISession, didRemove nearbyObjects: [NINearbyObject],
    reason: NINearbyObject.RemovalReason
  ) {
    guard let id = peerId(of: session) else { return }
    emit(["peerId": id, "lost": true])
    // Out of range for a moment: keep trying with the same token.
    if reason == .timeout, let config = configs[id] { session.run(config) }
  }

  func sessionSuspensionEnded(_ session: NISession) {
    // The app came back to the screen: carry on measuring.
    if let id = peerId(of: session), let config = configs[id] { session.run(config) }
  }

  func session(_ session: NISession, didInvalidateWith error: Error) {
    guard let id = peerId(of: session) else { return }
    sessions[id] = nil
    configs[id] = nil
    emit(["peerId": id, "lost": true])
  }

  // MARK: FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
