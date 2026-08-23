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
  private var generation = 0
  private var noiseCancelling = true
  private var queuedPlaybackFrames: AVAudioFramePosition = 0

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
        noiseCancelling: args?["noiseCancelling"] as? Bool ?? true,
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
      flushPlayback()
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

  private func startNative(
    captureId: String?,
    renderId: String?,
    noiseCancelling: Bool,
    result: @escaping FlutterResult
  ) {
    selectedCaptureId = captureId
    selectedRenderId = renderId
    self.noiseCancelling = noiseCancelling
    generation += 1
    do {
      try configureSession()
      try startEngine()
      running = true
      paused = false
      emitCatalog()
      emitIsolation()
      emitRoute()
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
      options: [.allowBluetooth, .allowBluetoothA2DP]
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
    queuedPlaybackFrames = 0
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
    let at: AVAudioTime?
    if let last = player.lastRenderTime {
      at = AVAudioTime(
        sampleTime: last.sampleTime + queuedPlaybackFrames,
        atRate: format.sampleRate
      )
    } else {
      at = nil
    }
    player.scheduleBuffer(buffer, at: at, options: [], completionHandler: nil)
    queuedPlaybackFrames += AVAudioFramePosition(frames)
  }

  private func flushPlayback() {
    player?.stop()
    queuedPlaybackFrames = 0
    if running, !paused {
      player?.play()
    }
  }

  private func selectEndpoints(captureId: String?, renderId: String?) {
    if let captureId { selectedCaptureId = captureId }
    if let renderId { selectedRenderId = renderId }
    applyRoute()
    do {
      try startEngine()
      emitRoute()
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
      let wanted = pairKey(selectedCaptureId)
      if let match = inputs.first(where: { pairId(for: $0) == wanted }) {
        return match
      }
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
    var seenPairs = Set(["handset", "speakerphone"])
    for input in session.availableInputs ?? [] {
      appendAccessory(input.portType, input.portName, input.uid, &items, &seenPairs)
    }
    for output in session.currentRoute.outputs {
      appendAccessory(output.portType, output.portName, output.uid, &items, &seenPairs)
    }
    return items
  }

  private func appendAccessory(
    _ portType: AVAudioSession.Port,
    _ name: String,
    _ uid: String,
    _ items: inout [[String: Any]],
    _ seenPairs: inout Set<String>
  ) {
    let route = routeClass(for: portType)
    if route == "handset" || route == "speakerphone" { return }
    let pair = applePairId(route, name, uid)
    if seenPairs.contains(pair) { return }
    seenPairs.insert(pair)
    items.append(endpoint("\(pair)-in", name, route, true, pair))
    items.append(endpoint("\(pair)-out", name, route, false, pair))
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

  private func pairKey(_ endpointId: String) -> String {
    if endpointId.hasSuffix("-in") {
      return String(endpointId.dropLast(3))
    }
    if endpointId.hasSuffix("-out") {
      return String(endpointId.dropLast(4))
    }
    return endpointId
  }

  private func pairId(for port: AVAudioSessionPortDescription) -> String {
    applePairId(routeClass(for: port.portType), port.portName, port.uid)
  }

  private func applePairId(_ route: String, _ name: String, _ uid: String) -> String {
    switch route {
    case "handset":
      return "handset"
    case "speakerphone":
      return "speakerphone"
    default:
      var normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      for suffix in [" microphone", " mic", " speaker", " headphones", " headset"] {
        if normalized.hasSuffix(suffix) {
          normalized = String(normalized.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
      }
      return normalized.isEmpty ? uid : normalized
    }
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
    if #available(iOS 15.0, *) {
      if AVAudioSession.sharedInstance().preferredMicrophoneMode == .voiceIsolation {
        return "on"
      }
      return noiseCancelling ? "required" : "off"
    }
    let session = AVAudioSession.sharedInstance()
    let selector = NSSelectorFromString("preferredMicrophoneMode")
    guard session.responds(to: selector),
          let raw = session.perform(selector)?.takeUnretainedValue() as? Int
    else {
      return "unavailable"
    }
    // AVAudioSession.MicrophoneMode.voiceIsolation
    if raw == 2 {
      return "on"
    }
    return noiseCancelling ? "required" : "off"
  }

  private func openIsolationSettings() {
    if #available(iOS 15.0, *) {
      let hold = running && !paused
      if hold {
        engine?.pause()
        try? AVAudioSession.sharedInstance().setActive(
          false,
          options: .notifyOthersOnDeactivation
        )
      }
      AVCaptureDevice.showSystemUserInterface(.microphoneModes)
      if hold {
        try? AVAudioSession.sharedInstance().setActive(true)
        try? engine?.start()
        player?.play()
      }
      emitIsolation()
      return
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
    emitRoute()
    emitPath(alive: !AVAudioSession.sharedInstance().currentRoute.outputs.isEmpty)
  }

  private func emitRoute() {
    let session = AVAudioSession.sharedInstance()
    let ids = catalogIds(from: session)
    eventSink?(
      [
        "type": "route",
        "payload": [
          "captureId": ids.capture as Any,
          "renderId": ids.render as Any,
          "generation": generation,
        ],
      ]
    )
  }

  private func catalogIds(from session: AVAudioSession) -> (capture: String?, render: String?) {
    if let output = session.currentRoute.outputs.first {
      switch routeClass(for: output.portType) {
      case "speakerphone":
        return ("speaker-in", "speaker-out")
      case "handset":
        return ("handset-in", "handset-out")
      default:
        let pair = pairId(for: output)
        return ("\(pair)-in", "\(pair)-out")
      }
    }
    if let input = session.currentRoute.inputs.first {
      let pair = pairId(for: input)
      return ("\(pair)-in", "\(pair)-out")
    }
    return (nil, nil)
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
