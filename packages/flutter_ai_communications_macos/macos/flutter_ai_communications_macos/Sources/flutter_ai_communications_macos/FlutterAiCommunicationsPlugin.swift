import AVFoundation
import AudioToolbox
import CoreAudio
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
  private var captureTapInstalled = false
  private var watchingDevices = false
  private let camera = MacCameraGraph()
  private let screen = MacScreenGraph()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FlutterAiCommunicationsPlugin()
    instance.camera.attach(textures: registrar.textures)
    instance.screen.attach(textures: registrar.textures)
    instance.screen.attachCatalog { [weak instance] sources in
      instance?.eventSink?(["type": "screenCatalog", "payload": sources])
    }
    instance.camera.onCatalog = { [weak instance] cameras in
      instance?.eventSink?(["type": "cameraCatalog", "payload": cameras])
    }
    instance.camera.startCatalogWatch()
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
      result(startedFormatMap())
    case "openIsolationSettings":
      emitIsolation()
      result(nil)
    case "flushPlayback":
      flushPlayback()
      result(nil)
    case "enumerateCameras":
      result(camera.enumerate())
    case "requestCameraPermission":
      camera.requestPermission(result: result)
    case "startCameraNative":
      let args = call.arguments as? [String: Any]
      result(
        camera.start(
          cameraId: args?["cameraId"] as? String,
          width: args?["width"] as? Int ?? 1280,
          height: args?["height"] as? Int ?? 720,
          enabled: args?["enabled"] as? Bool ?? true,
          muted: args?["muted"] as? Bool ?? false
        )
      )
    case "stopCameraNative":
      camera.stop()
      result(nil)
    case "selectCameraNative":
      if let id = (call.arguments as? [String: Any])?["cameraId"] as? String {
        camera.select(cameraId: id)
      }
      result(nil)
    case "setCameraEnabledNative":
      camera.setEnabled((call.arguments as? [String: Any])?["enabled"] as? Bool ?? true)
      result(nil)
    case "setMuteVideoNative":
      camera.setMuted((call.arguments as? [String: Any])?["muted"] as? Bool ?? false)
      result(nil)
    case "setVideoProcessorNative":
      var args = call.arguments as? [String: Any] ?? [:]
      if let typed = args["bytes"] as? FlutterStandardTypedData {
        args["bytes"] = typed.data
      }
      result(camera.setProcessor(args))
    case "cameraGraphStats":
      result(camera.stats())
    case "enumerateScreenSources":
      screen.enumerate(result: result)
    case "requestScreenPermission":
      screen.requestPermission(result: result)
    case "beginScreenPickNative":
      screen.beginPick(result: result)
    case "endScreenPickNative":
      screen.endPick()
      result(nil)
    case "indicateScreenSourceNative":
      screen.indicate(sourceId: (call.arguments as? [String: Any])?["sourceId"] as? String)
      result(nil)
    case "startScreenShareNative":
      let args = call.arguments as? [String: Any]
      screen.start(
        sourceId: args?["sourceId"] as? String ?? "",
        includeSystemAudio: args?["includeSystemAudio"] as? Bool ?? false,
        cursor: args?["cursor"] as? Bool ?? true,
        motion: args?["motion"] as? Bool ?? false,
        result: result
      )
    case "stopScreenShareNative":
      screen.stop()
      result(nil)
    case "setIncludeSystemAudioNative":
      result(screen.setIncludeSystemAudio((call.arguments as? [String: Any])?["enabled"] as? Bool ?? false))
    case "setScreenMotionNative":
      screen.setMotion((call.arguments as? [String: Any])?["motion"] as? Bool ?? false)
      result(nil)
    case "setScreenCursorNative":
      screen.setCursor((call.arguments as? [String: Any])?["cursor"] as? Bool ?? true)
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
    if sink != nil {
      startDeviceWatch()
    } else {
      stopDeviceWatch()
    }
  }

  fileprivate func emitCatalogFromWatch() {
    emitCatalog()
  }

  private func startDeviceWatch() {
    guard !watchingDevices else { return }
    watchingDevices = true
    let client = Unmanaged.passUnretained(self).toOpaque()
    listen(kAudioHardwarePropertyDevices, client)
    listen(kAudioHardwarePropertyDefaultInputDevice, client)
    listen(kAudioHardwarePropertyDefaultOutputDevice, client)
  }

  private func stopDeviceWatch() {
    guard watchingDevices else { return }
    watchingDevices = false
    let client = Unmanaged.passUnretained(self).toOpaque()
    unlisten(kAudioHardwarePropertyDevices, client)
    unlisten(kAudioHardwarePropertyDefaultInputDevice, client)
    unlisten(kAudioHardwarePropertyDefaultOutputDevice, client)
  }

  private func listen(_ selector: AudioObjectPropertySelector, _ client: UnsafeMutableRawPointer) {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectAddPropertyListener(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      macosAudioDeviceListener,
      client
    )
  }

  private func unlisten(_ selector: AudioObjectPropertySelector, _ client: UnsafeMutableRawPointer) {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectRemovePropertyListener(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      macosAudioDeviceListener,
      client
    )
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
      result(startedFormatMap())
    } catch {
      let line = "fac.audio start failed \(error)\n"
      NSLog("%@", line)
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("fac.audio.log")
      try? line.write(to: url, atomically: true, encoding: .utf8)
      result("failed")
    }
  }

  private func stopNative() {
    running = false
    teardownEngine()
  }

  private func presentId(_ id: String?) -> String? {
    guard let id, !id.isEmpty else { return nil }
    return id
  }

  private func wantsCapture() -> Bool {
    presentId(selectedCaptureId) != nil || presentId(selectedRenderId) == nil
  }

  private func wantsPlayback() -> Bool {
    presentId(selectedRenderId) != nil || presentId(selectedCaptureId) == nil
  }

  private func startEngine() throws {
    let wantCapture = wantsCapture()
    let wantPlayback = wantsPlayback()
    if wantCapture {
      emitSilenceFrame()
    }
    teardownEngine()
    let next = AVAudioEngine()
    bindDevice(to: next.inputNode, endpointId: selectedCaptureId)
    bindDevice(to: next.outputNode, endpointId: selectedRenderId)
    let mixerFormat = next.mainMixerNode.outputFormat(forBus: 0)
    let inputFormat = next.inputNode.outputFormat(forBus: 0)
    var playerNode: AVAudioPlayerNode?
    var playerFormat: AVAudioFormat?
    if wantPlayback {
      let node = AVAudioPlayerNode()
      next.attach(node)
      let format = try Self.makePlaybackFormat(
        inputFormat: inputFormat,
        mixerFormat: mixerFormat
      )
      // Capture + playback share this one engine. Mixer is the VPIO reference.
      next.connect(node, to: next.mainMixerNode, format: format)
      playerNode = node
      playerFormat = format
    }
    next.connect(next.mainMixerNode, to: next.outputNode, format: nil)

    if wantCapture {
      // Voice Processing on a USB composite (BRIO mic+camera) resets the
      // UVC function: AVCaptureSession starts, then AVErrorDeviceWasDisconnected.
      let captureIsBuiltIn =
        selectedCaptureId?.localizedCaseInsensitiveContains("BuiltIn") == true
      let enableVoiceProcessing = noiseCancelling && captureIsBuiltIn
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
      captureTapInstalled = true
    }
    try next.start()
    engine = next
    player = playerNode
    playbackFormat = playerFormat
    queuedPlaybackFrames = 0
    playerNode?.play()
  }

  private func teardownEngine() {
    if let engine {
      if engine.inputNode.isVoiceProcessingEnabled {
        try? engine.inputNode.setVoiceProcessingEnabled(false)
      }
      if captureTapInstalled {
        engine.inputNode.removeTap(onBus: 0)
      }
      player?.stop()
      engine.stop()
    }
    engine = nil
    player = nil
    playbackFormat = nil
    captureTapInstalled = false
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

  private func startedFormatMap() -> [String: Any] {
    var map: [String: Any] = ["status": "started"]
    if wantsCapture() {
      let captureRate = engine?.inputNode.outputFormat(forBus: 0).sampleRate ?? 24_000
      map["nativeCaptureFormat"] = formatMap(sampleRate: captureRate)
    }
    if wantsPlayback() {
      let playRate = playbackFormat?.sampleRate
        ?? engine?.inputNode.outputFormat(forBus: 0).sampleRate
        ?? 24_000
      map["nativePlaybackFormat"] = formatMap(sampleRate: playRate)
    }
    return map
  }

  private func formatMap(sampleRate: Double, channels: Int = 1) -> [String: Any] {
    let rate = sampleRate > 0 ? Int(sampleRate.rounded()) : 24_000
    let ch = channels > 0 ? channels : 1
    return [
      "encoding": "pcm16le",
      "sampleRate": rate,
      "channels": ch,
    ]
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
    var items: [[String: Any]] = []
    let defaultIn = defaultDeviceID(kAudioHardwarePropertyDefaultInputDevice)
    let defaultOut = defaultDeviceID(kAudioHardwarePropertyDefaultOutputDevice)
    for id in audioDeviceIDs() {
      let name = stringProperty(id, kAudioObjectPropertyName) ?? "Endpoint"
      let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) ?? "\(id)"
      let transport = transportName(id)
      let route = routeClass(name: name, transport: transport)
      let pairId = pairIdentity(route: route, uid: uid, name: name)
      let hasInput = hasStreams(id, scope: kAudioDevicePropertyScopeInput)
      let hasOutput = hasStreams(id, scope: kAudioDevicePropertyScopeOutput)
      if hasInput {
        items.append(
          endpoint(
            uid,
            name,
            route,
            true,
            pairId,
            osDefault: id == defaultIn
          )
        )
      }
      if hasOutput {
        let renderId = hasInput ? "\(uid)-out" : uid
        items.append(
          endpoint(
            renderId,
            name,
            route,
            false,
            pairId,
            osDefault: id == defaultOut
          )
        )
      }
    }
    return items
  }

  private func endpoint(
    _ id: String,
    _ name: String,
    _ route: String,
    _ capture: Bool,
    _ pairId: String,
    osDefault: Bool = false
  ) -> [String: Any] {
    [
      "id": id,
      "name": name,
      "routeClass": route,
      "isCapture": capture,
      "pairId": pairId,
      "osDefault": osDefault,
      "capabilities": [
        "formFactor": "unknown",
        "aec": false,
        "ns": false,
        "agc": false,
        "carConnected": false,
      ],
    ]
  }

  private func bindDevice(to node: AVAudioNode, endpointId: String?) {
    guard let endpointId else {
      return
    }
    let resolved: String
    switch endpointId {
    case "built-in-in":
      if let id = defaultDeviceID(kAudioHardwarePropertyDefaultInputDevice),
         let uid = stringProperty(id, kAudioDevicePropertyDeviceUID)
      {
        resolved = uid
      } else {
        resolved = endpointId
      }
    case "built-in-out":
      if let id = defaultDeviceID(kAudioHardwarePropertyDefaultOutputDevice),
         let uid = stringProperty(id, kAudioDevicePropertyDeviceUID)
      {
        resolved = "\(uid)-out"
      } else {
        resolved = endpointId
      }
    default:
      resolved = endpointId
    }
    let uid = coreUID(resolved)
    guard let deviceID = deviceID(forUID: uid) else {
      return
    }
    node.auAudioUnit.setValue(NSNumber(value: deviceID), forKey: "deviceID")
  }

  private func coreUID(_ endpointId: String) -> String {
    if endpointId.hasSuffix("-out") {
      return String(endpointId.dropLast(4))
    }
    return endpointId
  }

  private func audioDeviceIDs() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == noErr else {
      return []
    }
    let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var ids = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &dataSize, &ids) == noErr else {
      return []
    }
    return ids
  }

  private func defaultDeviceID(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var id = AudioDeviceID()
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &id) == noErr else {
      return nil
    }
    return id
  }

  private func deviceID(forUID uid: String) -> AudioDeviceID? {
    for id in audioDeviceIDs() {
      if stringProperty(id, kAudioDevicePropertyDeviceUID) == uid {
        return id
      }
    }
    return nil
  }

  private func hasStreams(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams,
      mScope: scope,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else {
      return false
    }
    return size > 0
  }

  private func stringProperty(
    _ id: AudioDeviceID,
    _ selector: AudioObjectPropertySelector
  ) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else {
      return nil
    }
    var cf: Unmanaged<CFString>?
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &cf) == noErr else {
      return nil
    }
    return cf?.takeUnretainedValue() as String?
  }

  private func transportName(_ id: AudioDeviceID) -> String {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var code: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &code) == noErr else {
      return ""
    }
    let scalars: [UInt8] = [
      UInt8((code >> 24) & 0xff),
      UInt8((code >> 16) & 0xff),
      UInt8((code >> 8) & 0xff),
      UInt8(code & 0xff),
    ]
    return String(bytes: scalars, encoding: .ascii)?
      .trimmingCharacters(in: .whitespaces) ?? ""
  }

  private func routeClass(name: String, transport: String) -> String {
    let n = name.lowercased()
    let t = transport.lowercased()
    if t.contains("blue") || n.contains("bluetooth") {
      return "bluetooth"
    }
    if n.contains("headset") ||
      n.contains("headphone") ||
      n.contains("earphone") ||
      t.contains("usb")
    {
      return "wired"
    }
    if n.contains("speaker") ||
      n.contains("microphone") ||
      n.contains("built-in") ||
      n.contains("macbook") ||
      t.contains("bltn") ||
      t.contains("pci")
    {
      return "speakerphone"
    }
    return "wired"
  }

  private func pairIdentity(route: String, uid: String, name: String) -> String {
    if route == "speakerphone" {
      return "built-in"
    }
    var normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    for suffix in [" microphone", " mic", " speaker", " headphones", " headset"] {
      if normalized.hasSuffix(suffix) {
        normalized = String(normalized.dropLast(suffix.count))
          .trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }
    return normalized.isEmpty ? uid : normalized
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

private let macosAudioDeviceListener: AudioObjectPropertyListenerProc = {
  _,
  _,
  _,
  client in
  guard let client else { return noErr }
  let plugin = Unmanaged<FlutterAiCommunicationsPlugin>.fromOpaque(client)
    .takeUnretainedValue()
  DispatchQueue.main.async {
    plugin.emitCatalogFromWatch()
  }
  return noErr
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
