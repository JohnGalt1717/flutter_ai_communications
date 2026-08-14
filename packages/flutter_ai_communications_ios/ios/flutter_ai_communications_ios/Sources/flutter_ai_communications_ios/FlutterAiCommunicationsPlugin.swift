import AVFoundation
import Flutter
import UIKit

public class FlutterAiCommunicationsPlugin: NSObject, FlutterPlugin {
  private let methods = "flutter_ai_communications/methods"
  private let captureName = "flutter_ai_communications/capture"
  private let eventsName = "flutter_ai_communications/events"

  private var captureSink: FlutterEventSink?
  private var eventSink: FlutterEventSink?
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var selectedCaptureId: String?
  private var selectedRenderId: String?
  private var paused = false
  private var running = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FlutterAiCommunicationsPlugin()
    let messenger = registrar.messenger()
    let methods = FlutterMethodChannel(name: instance.methods, binaryMessenger: messenger)
    registrar.addMethodCallDelegate(instance, channel: methods)
    FlutterEventChannel(name: instance.captureName, binaryMessenger: messenger)
      .setStreamHandler(CaptureHandler(plugin: instance))
    FlutterEventChannel(name: instance.eventsName, binaryMessenger: messenger)
      .setStreamHandler(EventHandler(plugin: instance))
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "enumerateEndpoints":
      result(enumerateEndpoints())
    case "requestMicrophonePermission":
      requestPermission(result: result)
    case "startNative":
      let args = call.arguments as? [String: Any]
      startNative(
        captureId: args?["captureId"] as? String,
        renderId: args?["renderId"] as? String,
        result: result
      )
    case "stopNative":
      stopNative()
      result(nil)
    case "pauseNative":
      paused = true
      engine?.pause()
      result(nil)
    case "resumeNative":
      paused = false
      try? engine?.start()
      result(nil)
    case "play":
      play(call.arguments as? FlutterStandardTypedData)
      result(nil)
    case "selectEndpoints":
      let args = call.arguments as? [String: Any]
      selectEndpoints(
        captureId: args?["captureId"] as? String,
        renderId: args?["renderId"] as? String
      )
      result(nil)
    case "openIsolationSettings":
      openIsolationSettings()
      result(nil)
    case "flushPlayback":
      player?.stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  fileprivate func attachCapture(_ sink: FlutterEventSink?) {
    captureSink = sink
  }

  fileprivate func attachEvents(_ sink: FlutterEventSink?) {
    eventSink = sink
  }

  private func requestPermission(result: @escaping FlutterResult) {
    if #available(iOS 17.0, *) {
      AVAudioApplication.requestRecordPermission { granted in
        result(granted ? "granted" : "denied")
      }
      return
    }
    AVAudioSession.sharedInstance().requestRecordPermission { granted in
      result(granted ? "granted" : "denied")
    }
  }

  private func startNative(captureId: String?, renderId: String?, result: @escaping FlutterResult) {
    selectedCaptureId = captureId
    selectedRenderId = renderId
    do {
      try configureSession()
      try startEngine()
      running = true
      paused = false
      emitCatalog()
      emitIsolation()
      result("started")
    } catch {
      result("failed")
    }
  }

  private func stopNative() {
    running = false
    engine?.inputNode.removeTap(onBus: 0)
    engine?.stop()
    player?.stop()
    engine = nil
    player = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func configureSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playAndRecord,
      mode: .voiceChat,
      options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
    )
    try session.setPreferredSampleRate(24_000)
    try session.setActive(true)
    applyRoute()
    NotificationCenter.default.removeObserver(self)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleRouteChange),
      name: AVAudioSession.routeChangeNotification,
      object: session
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleInterruption),
      name: AVAudioSession.interruptionNotification,
      object: session
    )
  }

  private func startEngine() throws {
    emitSilenceFrame()
    engine?.inputNode.removeTap(onBus: 0)
    engine?.stop()
    let next = AVAudioEngine()
    let playerNode = AVAudioPlayerNode()
    next.attach(playerNode)
    let format = next.inputNode.outputFormat(forBus: 0)
    next.connect(playerNode, to: next.mainMixerNode, format: format)
    next.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      self?.emitCapture(buffer)
    }
    try next.start()
    engine = next
    player = playerNode
    playerNode.play()
  }

  private func emitCapture(_ buffer: AVAudioPCMBuffer) {
    if paused || !running { return }
    guard let channel = buffer.int16ChannelData?[0] else {
      if let floats = buffer.floatChannelData?[0] {
        let count = Int(buffer.frameLength)
        var bytes = [UInt8](repeating: 0, count: count * 2)
        for i in 0..<count {
          let sample = Int16((floats[i] * 32767).rounded())
          bytes[i * 2] = UInt8(truncatingIfNeeded: sample)
          bytes[i * 2 + 1] = UInt8(truncatingIfNeeded: sample >> 8)
        }
        captureSink?(FlutterStandardTypedData(bytes: Data(bytes)))
      }
      return
    }
    let count = Int(buffer.frameLength)
    let data = Data(bytes: channel, count: count * 2)
    captureSink?(FlutterStandardTypedData(bytes: data))
  }

  private func emitSilenceFrame() {
    captureSink?(FlutterStandardTypedData(bytes: Data(repeating: 0, count: 480)))
  }

  private func play(_ data: FlutterStandardTypedData?) {
    guard let data, let engine, let player, running, !paused else { return }
    let format = engine.mainMixerNode.outputFormat(forBus: 0)
    let frames = UInt32(data.data.count / 2)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
    buffer.frameLength = frames
    if let dest = buffer.int16ChannelData?[0] {
      data.data.copyBytes(to: UnsafeMutableBufferPointer(start: dest, count: Int(frames)))
    } else if let dest = buffer.floatChannelData?[0] {
      let samples = data.data.withUnsafeBytes { raw -> [Int16] in
        Array(raw.bindMemory(to: Int16.self))
      }
      for i in 0..<Int(frames) {
        dest[i] = Float(samples[i]) / 32768.0
      }
    }
    player.scheduleBuffer(buffer, completionHandler: nil)
  }

  private func selectEndpoints(captureId: String?, renderId: String?) {
    if let captureId { selectedCaptureId = captureId }
    if let renderId { selectedRenderId = renderId }
    applyRoute()
    do {
      try startEngine()
    } catch {
      emitPath(alive: false)
    }
  }

  private func applyRoute() {
    let session = AVAudioSession.sharedInstance()
    if selectedRenderId == "speakerphone-out" || selectedRenderId == "speaker-out" {
      try? session.overrideOutputAudioPort(.speaker)
    } else {
      try? session.overrideOutputAudioPort(.none)
    }
    if let preferred = preferredInput() {
      try? session.setPreferredInput(preferred)
    }
  }

  private func preferredInput() -> AVAudioSessionPortDescription? {
    let session = AVAudioSession.sharedInstance()
    let inputs = session.availableInputs ?? []
    if let selectedCaptureId {
      if let match = inputs.first(where: { $0.uid == selectedCaptureId }) {
        return match
      }
    }
    return session.preferredInput
  }

  private func enumerateEndpoints() -> [[String: Any]] {
    let session = AVAudioSession.sharedInstance()
    var items: [[String: Any]] = [
      endpoint("handset-in", "Handset", "handset", true, "handset"),
      endpoint("handset-out", "Handset", "handset", false, "handset"),
      endpoint("speaker-in", "Speakerphone", "speakerphone", true, "speakerphone"),
      endpoint("speaker-out", "Speakerphone", "speakerphone", false, "speakerphone"),
    ]
    for input in session.availableInputs ?? [] {
      let route = routeClass(for: input.portType)
      if route == "handset" || route == "speakerphone" { continue }
      items.append(endpoint(input.uid, input.portName, route, true, input.uid))
    }
    for output in session.currentRoute.outputs {
      let route = routeClass(for: output.portType)
      if route == "handset" || route == "speakerphone" { continue }
      items.append(endpoint(output.uid, output.portName, route, false, output.uid))
    }
    return items
  }

  private func endpoint(
    _ id: String,
    _ name: String,
    _ route: String,
    _ capture: Bool,
    _ pairId: String
  ) -> [String: Any] {
    [
      "id": id,
      "name": name,
      "routeClass": route,
      "isCapture": capture,
      "pairId": pairId,
    ]
  }

  private func routeClass(for port: AVAudioSession.Port) -> String {
    switch port {
    case .builtInMic, .builtInReceiver:
      return "handset"
    case .builtInSpeaker:
      return "speakerphone"
    case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE:
      return "bluetooth"
    case .headphones, .headsetMic, .usbAudio:
      return "wired"
    case .carAudio:
      return "car"
    default:
      return "wired"
    }
  }

  private func emitCatalog() {
    eventSink?(["type": "catalog", "payload": enumerateEndpoints()])
  }

  private func emitIsolation() {
    eventSink?(["type": "isolation", "payload": isolationState()])
  }

  private func isolationState() -> String {
    let session = AVAudioSession.sharedInstance()
    let selector = NSSelectorFromString("preferredMicrophoneMode")
    guard session.responds(to: selector),
          let raw = session.perform(selector)?.takeUnretainedValue() as? Int
    else {
      return "unavailable"
    }
    // AVAudioSession.MicrophoneMode.voiceIsolation
    return raw == 2 ? "on" : "off"
  }

  private func openIsolationSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
      DispatchQueue.main.async {
        UIApplication.shared.open(url)
      }
    }
    emitIsolation()
  }

  private func emitPath(alive: Bool) {
    var payload: [String: Any] = ["alive": alive]
    if !alive {
      payload["reason"] = "pathDead"
    }
    eventSink?(["type": "path", "payload": payload])
  }

  @objc private func handleRouteChange(_ notification: Notification) {
    emitCatalog()
    let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
    let inputs = AVAudioSession.sharedInstance().currentRoute.inputs
    eventSink?(
      [
        "type": "route",
        "payload": [
          "captureId": inputs.first?.uid as Any,
          "renderId": outputs.first?.uid as Any,
        ],
      ]
    )
    emitPath(alive: !outputs.isEmpty)
  }

  @objc private func handleInterruption(_ notification: Notification) {
    let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
    if type == AVAudioSession.InterruptionType.began.rawValue {
      eventSink?(["type": "focus", "payload": "interrupted"])
    } else {
      eventSink?(["type": "focus", "payload": "active"])
    }
  }
}

private final class CaptureHandler: NSObject, FlutterStreamHandler {
  weak var plugin: FlutterAiCommunicationsPlugin?
  init(plugin: FlutterAiCommunicationsPlugin) { self.plugin = plugin }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    plugin?.attachCapture(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    plugin?.attachCapture(nil)
    return nil
  }
}

private final class EventHandler: NSObject, FlutterStreamHandler {
  weak var plugin: FlutterAiCommunicationsPlugin?
  init(plugin: FlutterAiCommunicationsPlugin) { self.plugin = plugin }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    plugin?.attachEvents(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    plugin?.attachEvents(nil)
    return nil
  }
}
