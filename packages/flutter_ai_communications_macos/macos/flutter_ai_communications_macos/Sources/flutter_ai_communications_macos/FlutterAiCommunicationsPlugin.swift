import AVFoundation
import FlutterMacOS

/// One duplex AVAudioEngine for capture and playback.
///
/// Isolation is unavailable on macOS. The Session still emits Isolation
/// unavailable and raises the Sound floor. VoiceProcessingIO still needs the
/// rendered playback reference on the same engine — separate AudioQueues were
/// the Scribe speaker leak.
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
  private var voiceProcessingEnabled = false
  private var queuedPlaybackFrames: AVAudioFramePosition = 0
  private var playbackFormat: AVAudioFormat?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FlutterAiCommunicationsPlugin()
    let messenger = registrar.messenger
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
      emitIsolation()
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
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      result("granted")
    case .denied, .restricted:
      result("denied")
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        // FlutterResult must be invoked on the platform-channel thread (main).
        DispatchQueue.main.async {
          result(granted ? "granted" : "denied")
        }
      }
    @unknown default:
      result("denied")
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
    teardownEngine()
  }

  private func startEngine() throws {
    emitSilenceFrame()
    teardownEngine()
    let next = AVAudioEngine()
    let playerNode = AVAudioPlayerNode()
    next.attach(playerNode)
    let mixerFormat = next.mainMixerNode.outputFormat(forBus: 0)
    let inputFormat = next.inputNode.outputFormat(forBus: 0)
    let playerFormat = try Self.makePlaybackFormat(
      inputFormat: inputFormat,
      mixerFormat: mixerFormat
    )
    // Capture + playback share this one engine. Mixer is the VPIO reference.
    next.connect(playerNode, to: next.mainMixerNode, format: playerFormat)
    next.connect(next.mainMixerNode, to: next.outputNode, format: nil)

    let enableVoiceProcessing = noiseCancelling
    if enableVoiceProcessing {
      do {
        try next.inputNode.setVoiceProcessingEnabled(true)
        if next.inputNode.isVoiceProcessingBypassed {
          next.inputNode.isVoiceProcessingBypassed = false
        }
        voiceProcessingEnabled = next.inputNode.isVoiceProcessingEnabled
      } catch {
        voiceProcessingEnabled = false
      }
    } else if next.inputNode.isVoiceProcessingEnabled {
      try? next.inputNode.setVoiceProcessingEnabled(false)
      voiceProcessingEnabled = false
    } else {
      voiceProcessingEnabled = false
    }

    let processedInput = next.inputNode.outputFormat(forBus: 0)
    let tapChannels = processedInput.channelCount > 0 ? Int(processedInput.channelCount) : 1
    let tapFormat = captureTapFormat(inputFormat: processedInput, channels: min(tapChannels, 1))
    next.inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
      self?.emitCapture(buffer)
    }
    try next.start()
    engine = next
    player = playerNode
    playbackFormat = playerFormat
    queuedPlaybackFrames = 0
    playerNode.play()
  }

  private func teardownEngine() {
    if let engine {
      if engine.inputNode.isVoiceProcessingEnabled {
        try? engine.inputNode.setVoiceProcessingEnabled(false)
      }
      engine.inputNode.removeTap(onBus: 0)
      player?.stop()
      engine.stop()
    }
    engine = nil
    player = nil
    playbackFormat = nil
    voiceProcessingEnabled = false
  }

  private func captureTapFormat(inputFormat: AVAudioFormat, channels: Int) -> AVAudioFormat? {
    guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else { return nil }
    if inputFormat.channelCount == AVAudioChannelCount(channels) {
      return inputFormat
    }
    return AVAudioFormat(
      commonFormat: inputFormat.commonFormat,
      sampleRate: inputFormat.sampleRate,
      channels: AVAudioChannelCount(channels),
      interleaved: inputFormat.isInterleaved
    )
  }

  private static func makePlaybackFormat(
    inputFormat: AVAudioFormat,
    mixerFormat: AVAudioFormat
  ) throws -> AVAudioFormat {
    let sampleRate = mixerFormat.sampleRate > 0 ? mixerFormat.sampleRate : inputFormat.sampleRate
    let common = mixerFormat.sampleRate > 0 ? mixerFormat.commonFormat : inputFormat.commonFormat
    guard let format = AVAudioFormat(
      commonFormat: common,
      sampleRate: sampleRate,
      channels: 1,
      interleaved: false
    ) else {
      throw AVError(.fileFormatNotRecognized)
    }
    return format
  }

  private func emitCapture(_ buffer: AVAudioPCMBuffer) {
    if paused || !running { return }
    guard let channel = buffer.int16ChannelData?[0] else {
      if let floats = buffer.floatChannelData?[0] {
        let count = Int(buffer.frameLength)
        var bytes = [UInt8](repeating: 0, count: count * 2)
        for i in 0..<count {
          let clamped = max(-1.0, min(1.0, Double(floats[i])))
          let sample = Int16((clamped * 32767.0).rounded())
          bytes[i * 2] = UInt8(truncatingIfNeeded: sample)
          bytes[i * 2 + 1] = UInt8(truncatingIfNeeded: sample >> 8)
        }
        emitCaptureBytes(FlutterStandardTypedData(bytes: Data(bytes)))
      }
      return
    }
    let count = Int(buffer.frameLength)
    let data = Data(bytes: channel, count: count * 2)
    emitCaptureBytes(FlutterStandardTypedData(bytes: data))
  }

  private func emitSilenceFrame() {
    emitCaptureBytes(FlutterStandardTypedData(bytes: Data(repeating: 0, count: 480)))
  }

  private func emitCaptureBytes(_ data: FlutterStandardTypedData) {
    if Thread.isMainThread {
      captureSink?(data)
      return
    }
    DispatchQueue.main.async { [weak self] in
      self?.captureSink?(data)
    }
  }

  private func play(_ data: FlutterStandardTypedData?) {
    guard let data, let player, running, !paused else { return }
    guard let format = playbackFormat else { return }
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
    do {
      try startEngine()
      emitRoute()
      emitIsolation()
    } catch {
      emitPath(alive: false)
    }
  }

  private func enumerateEndpoints() -> [[String: Any]] {
    // Catalog remains best-effort from system default I/O names.
    // Pair identity for built-ins is "built-in"; accessories use UID.
    var items: [[String: Any]] = [
      endpoint("built-in-in", "Built-in Microphone", "speakerphone", true, "built-in"),
      endpoint("built-in-out", "Built-in Speakers", "speakerphone", false, "built-in"),
    ]
    if let captureId = selectedCaptureId, captureId != "built-in-in" {
      items.append(endpoint(captureId, captureId, "wired", true, captureId))
    }
    if let renderId = selectedRenderId, renderId != "built-in-out" {
      items.append(endpoint(renderId, renderId, "wired", false, renderId))
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
      "capabilities": [
        "formFactor": "unknown",
        "aec": false,
        "ns": false,
        "agc": false,
        "carConnected": false,
      ],
    ]
  }

  private func emitCatalog() {
    eventSink?(["type": "catalog", "payload": enumerateEndpoints()])
  }

  private func emitIsolation() {
    // macOS has no Isolation UI. Session raises the Sound floor on unavailable.
    eventSink?(["type": "isolation", "payload": "unavailable"])
  }

  private func emitPath(alive: Bool) {
    var payload: [String: Any] = ["alive": alive]
    if !alive {
      payload["reason"] = "pathDead"
    }
    eventSink?(["type": "path", "payload": payload])
  }

  private func emitRoute() {
    eventSink?(
      [
        "type": "route",
        "payload": [
          "captureId": selectedCaptureId as Any,
          "renderId": selectedRenderId as Any,
          "generation": generation,
        ],
      ]
    )
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
