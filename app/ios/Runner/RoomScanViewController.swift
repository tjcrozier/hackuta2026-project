import Flutter
import RoomPlan
import UIKit

/// Connects the Flutter channel "blackbox/roomplan" to Apple RoomPlan (LiDAR room scan).
///
/// Dart calls:
///   isSupported -> Bool (false on iPhones without LiDAR)
///   startScan   -> ["model": path to .usdz, "json": path to .json], or nil if cancelled
enum RoomPlanBridge {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "blackbox/roomplan", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isSupported":
        result(RoomCaptureSession.isSupported)
      case "startScan":
        startScan(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func startScan(result: @escaping FlutterResult) {
    guard RoomCaptureSession.isSupported else {
      result(FlutterError(code: "no_lidar", message: "This iPhone has no LiDAR.", details: nil))
      return
    }
    guard let top = topViewController() else {
      result(FlutterError(code: "no_screen", message: "Could not open the scanner.", details: nil))
      return
    }
    let scanner = RoomScanViewController()
    scanner.modalPresentationStyle = .fullScreen
    scanner.onFinish = result
    top.present(scanner, animated: true)
  }

  /// The view controller currently on screen.
  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}

/// Full-screen RoomPlan scanner with Cancel and Done buttons.
final class RoomScanViewController: UIViewController, RoomCaptureViewDelegate,
  RoomCaptureSessionDelegate
{
  /// Called exactly once with the file paths, nil (cancelled), or a FlutterError.
  var onFinish: FlutterResult?

  private var captureView: RoomCaptureView!
  private let doneButton = UIButton(type: .system)
  private let cancelButton = UIButton(type: .system)
  private let statusLabel = UILabel()
  private var finished = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black

    captureView = RoomCaptureView(frame: view.bounds)
    captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    captureView.delegate = self
    captureView.captureSession.delegate = self
    view.addSubview(captureView)

    style(cancelButton, title: "Cancel", background: UIColor(white: 0.1, alpha: 0.8))
    cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    // Accent color #C2410C, the main action color of the app.
    style(doneButton, title: "Done", background: UIColor(red: 0.76, green: 0.25, blue: 0.05, alpha: 1))
    doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

    statusLabel.text = "Walk slowly. Point at walls, doors and openings."
    statusLabel.textColor = .white
    statusLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 2
    statusLabel.backgroundColor = UIColor(white: 0, alpha: 0.5)
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(statusLabel)

    let guide = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      cancelButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
      cancelButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
      cancelButton.widthAnchor.constraint(equalToConstant: 110),
      cancelButton.heightAnchor.constraint(equalToConstant: 56),
      doneButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
      doneButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
      doneButton.widthAnchor.constraint(equalToConstant: 110),
      doneButton.heightAnchor.constraint(equalToConstant: 56),
      statusLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
      statusLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
      statusLabel.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
      statusLabel.heightAnchor.constraint(equalToConstant: 56),
    ])
  }

  private func style(_ button: UIButton, title: String, background: UIColor) {
    button.setTitle(title, for: .normal)
    button.setTitleColor(.white, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
    button.backgroundColor = background
    button.layer.cornerRadius = 14
    button.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(button)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
  }

  @objc private func doneTapped() {
    doneButton.isEnabled = false
    statusLabel.text = "Building the 3D model..."
    captureView.captureSession.stop()  // RoomPlan then calls captureView(didPresent:)
  }

  @objc private func cancelTapped() {
    captureView.captureSession.stop()
    finish(nil)
  }

  /// Report the result to Flutter once, then close the scanner.
  private func finish(_ value: Any?) {
    if finished { return }
    finished = true
    dismiss(animated: true) { [onFinish] in onFinish?(value) }
  }

  // MARK: RoomCaptureSessionDelegate

  func captureSession(
    _ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?
  ) {
    if let error = error {
      finish(FlutterError(code: "scan_failed", message: error.localizedDescription, details: nil))
    }
  }

  // MARK: RoomCaptureViewDelegate

  func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
    return true  // yes, turn the raw data into the final room
  }

  func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
    if finished { return }
    if let error = error {
      finish(FlutterError(code: "scan_failed", message: error.localizedDescription, details: nil))
      return
    }
    do {
      let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("scan-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let modelURL = folder.appendingPathComponent("room.usdz")
      let jsonURL = folder.appendingPathComponent("room.json")
      try processedResult.export(to: modelURL, exportOptions: .parametric)
      try JSONEncoder().encode(processedResult).write(to: jsonURL)
      finish(["model": modelURL.path, "json": jsonURL.path])
    } catch {
      finish(FlutterError(code: "export_failed", message: error.localizedDescription, details: nil))
    }
  }
}
