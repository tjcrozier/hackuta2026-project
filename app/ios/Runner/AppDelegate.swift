import AVFoundation
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
    VoiceService.shared.register(messenger: messenger)
  }
}

/// Athena's voice on the Athena Live call: Apple's built-in text-to-speech.
/// Speaks on the phone only; no audio is sent anywhere. (Kept in this file so it needs
/// no change to the Xcode project.)
///
/// MethodChannel "blackbox/voice":
///   speak(text)  speaks; the reply comes when it finishes (true) or is cut off (false)
///   stop         stops speaking now
final class VoiceService: NSObject, AVSpeechSynthesizerDelegate {
  static let shared = VoiceService()

  private let synthesizer = AVSpeechSynthesizer()
  private var pending: FlutterResult?  // answered when the current speech ends

  func register(messenger: FlutterBinaryMessenger) {
    synthesizer.delegate = self
    let methods = FlutterMethodChannel(name: "blackbox/voice", binaryMessenger: messenger)
    methods.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "speak":
        let text = (call.arguments as? [String: Any])?["text"] as? String ?? ""
        self.speak(text, result: result)
      case "stop":
        self.synthesizer.stopSpeaking(at: .immediate)
        self.finish(false)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func speak(_ text: String, result: @escaping FlutterResult) {
    synthesizer.stopSpeaking(at: .immediate)
    finish(false)  // the old answer was cut off
    guard !text.isEmpty else { return result(false) }
    // Speak even when the silent switch is on, and lower music while Athena talks.
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    try? session.setActive(true)
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    pending = result
    synthesizer.speak(utterance)
  }

  private func finish(_ completed: Bool) {
    guard let result = pending else { return }
    pending = nil
    result(completed)
    if !synthesizer.isSpeaking {
      // Let music and other apps come back to full volume.
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    finish(true)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    finish(false)
  }
}
