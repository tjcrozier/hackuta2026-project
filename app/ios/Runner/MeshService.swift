import Flutter
import MultipeerConnectivity

/// Offline mesh over Apple Multipeer Connectivity (Bluetooth + peer-to-peer Wi-Fi).
/// Phones on the same site find each other and connect by themselves, no internet needed.
///
/// MethodChannel "blackbox/mesh":
///   start(siteCode, workerId, name)  start advertising and browsing
///   stop()
///   send(json, except?)              send to all connected peers (except one, when forwarding)
/// EventChannel "blackbox/mesh/events" sends maps:
///   {event: "peer_connected", id, name}
///   {event: "peer_lost", id}
///   {event: "message", from, json}
final class MeshService: NSObject, FlutterStreamHandler, MCSessionDelegate,
  MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate
{
  static let shared = MeshService()

  private let serviceType = "bb-mesh"
  private var siteCode = ""
  private var selfId = ""
  private var selfName = ""

  private var peerID: MCPeerID?
  private var session: MCSession?
  private var advertiser: MCNearbyServiceAdvertiser?
  private var browser: MCNearbyServiceBrowser?
  private var eventSink: FlutterEventSink?

  /// Names of the phones we know about, by their id.
  private var names: [String: String] = [:]
  /// Phones currently visible to the browser (so we can invite them again after a drop).
  private var visible: [String: MCPeerID] = [:]

  func register(messenger: FlutterBinaryMessenger) {
    let methods = FlutterMethodChannel(name: "blackbox/mesh", binaryMessenger: messenger)
    methods.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "start":
        self.start(
          siteCode: args["siteCode"] as? String ?? "",
          workerId: args["workerId"] as? String ?? "",
          name: args["name"] as? String ?? "")
        result(nil)
      case "stop":
        self.stop()
        result(nil)
      case "send":
        self.send(json: args["json"] as? String ?? "", except: args["except"] as? String)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    FlutterEventChannel(name: "blackbox/mesh/events", binaryMessenger: messenger)
      .setStreamHandler(self)
  }

  // MARK: start / stop / send

  private func start(siteCode: String, workerId: String, name: String) {
    stop()
    guard !workerId.isEmpty else { return }
    self.siteCode = siteCode
    selfId = workerId
    selfName = name

    // The peer's display name is the worker id, so every message knows who it came from.
    let peer = MCPeerID(displayName: workerId)
    let newSession = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
    newSession.delegate = self
    peerID = peer
    session = newSession

    let info = ["site": siteCode, "id": workerId, "name": String(name.prefix(40))]
    advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: info, serviceType: serviceType)
    advertiser?.delegate = self
    advertiser?.startAdvertisingPeer()
    browser = MCNearbyServiceBrowser(peer: peer, serviceType: serviceType)
    browser?.delegate = self
    browser?.startBrowsingForPeers()
  }

  private func stop() {
    advertiser?.stopAdvertisingPeer()
    browser?.stopBrowsingForPeers()
    session?.disconnect()
    advertiser = nil
    browser = nil
    session = nil
    peerID = nil
    visible.removeAll()
  }

  private func send(json: String, except: String?) {
    guard let session = session, let data = json.data(using: .utf8) else { return }
    let peers = session.connectedPeers.filter { $0.displayName != except }
    if peers.isEmpty { return }
    try? session.send(data, toPeers: peers, with: .reliable)
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { self.eventSink?(event) }
  }

  // MARK: finding peers

  /// Both phones browse and advertise. To avoid two invitations crossing each other,
  /// only the phone with the "bigger" id sends the invitation.
  private func invite(_ peer: MCPeerID) {
    guard let session = session, let browser = browser, selfId > peer.displayName,
      !session.connectedPeers.contains(peer)
    else { return }
    // Tell the other phone who we are (it cannot see our discovery info).
    let hello = try? JSONSerialization.data(
      withJSONObject: ["site": siteCode, "id": selfId, "name": selfName])
    browser.invitePeer(peer, to: session, withContext: hello, timeout: 20)
  }

  func browser(
    _ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
    withDiscoveryInfo info: [String: String]?
  ) {
    guard info?["site"] == siteCode else { return }  // only phones on the same site
    DispatchQueue.main.async {
      self.names[peerID.displayName] = info?["name"] ?? ""
      self.visible[peerID.displayName] = peerID
      self.invite(peerID)
    }
  }

  func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
    DispatchQueue.main.async { self.visible[peerID.displayName] = nil }
  }

  func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
    emit(["event": "error", "message": error.localizedDescription])
  }

  func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void
  ) {
    let hello =
      context.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } ?? [:]
    let sameSite = hello["site"] == siteCode
    DispatchQueue.main.async {
      if sameSite { self.names[peerID.displayName] = hello["name"] ?? "" }
      invitationHandler(sameSite, sameSite ? self.session : nil)  // auto-accept same site
    }
  }

  func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error
  ) {
    emit(["event": "error", "message": error.localizedDescription])
  }

  // MARK: session

  func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
    DispatchQueue.main.async {
      guard session === self.session else { return }
      let id = peerID.displayName
      switch state {
      case .connected:
        self.eventSink?(["event": "peer_connected", "id": id, "name": self.names[id] ?? ""])
      case .notConnected:
        self.eventSink?(["event": "peer_lost", "id": id])
        // Still nearby? Try again in a moment.
        if let peer = self.visible[id] {
          DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.invite(peer) }
        }
      default:
        break
      }
    }
  }

  func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
    guard let json = String(data: data, encoding: .utf8) else { return }
    emit(["event": "message", "from": peerID.displayName, "json": json])
  }

  // Not used, but required by the protocol.
  func session(
    _ session: MCSession, didReceive stream: InputStream, withName streamName: String,
    fromPeer peerID: MCPeerID
  ) {}
  func session(
    _ session: MCSession, didStartReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID, with progress: Progress
  ) {}
  func session(
    _ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?
  ) {}

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
