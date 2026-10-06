import AVFoundation
import AudioToolbox
import CoreAudio
import FacExceptionCatch
import FlutterMacOS

private enum MacAudioEngineError: LocalizedError {
  case routeFailed

  var errorDescription: String? {
    switch self {
    case .routeFailed:
      return "route_failed"
    }
  }
}

extension FlutterAiCommunicationsPlugin {
  fileprivate static var routeFailedError: FlutterError {
    FlutterError(
      code: "route_failed",
      message: "post-start bind failed",
      details: nil
    )
  }
}

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
  private var playbackConverter: AVAudioConverter?
  private var captureConverter: AVAudioConverter?
  private var captureConverterFromRate: Double = 0
  private var captureConverterToRate: Double = 0
  private var captureTapInstalled = false
  private var captureTapFrames = 0
  private var scheduledPlaybackBuffers = 0
  private var isRebuildingGraph = false
  private let maxScheduledPlaybackBuffers = 12
  private let edgeSampleRate = 24_000.0
  /// Engine stop/start stay off the UI thread (Fieldist MacOSAudioEngine).
  private let audioQueue = DispatchQueue(
    label: "fac.macos.audio",
    qos: .userInitiated
  )
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

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    camera.stopCatalogWatch()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "enumerateEndpoints":
      result(enumerateEndpoints())
    case "beginCatalogObservation", "endCatalogObservation":
      result(nil)
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
      stopNative(result: result)
    case "pauseNative":
      paused = true
      audioQueue.async { [weak self] in
        self?.engine?.pause()
        DispatchQueue.main.async { result(nil) }
      }
    case "resumeNative":
      paused = false
      resumeEngine(result: result)
    case "play":
      let data = call.arguments as? FlutterStandardTypedData
      audioQueue.async { [weak self] in
        self?.play(data)
      }
      result(nil)
    case "selectEndpoints":
      let args = call.arguments as? [String: Any]
      selectEndpoints(
        captureId: args?["captureId"] as? String,
        renderId: args?["renderId"] as? String,
        result: result
      )
    case "openIsolationSettings":
      emitIsolation()
      result(nil)
    case "flushPlayback":
      audioQueue.async { [weak self] in
        self?.flushPlayback()
        DispatchQueue.main.async { result(nil) }
      }
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
    case "captureStillNative":
      result(camera.captureStill())
    case "captureScreenStillNative":
      result(screen.captureStill())
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
    let gen = generation
    running = true
    paused = false
    audioQueue.async { [weak self] in
      guard let self else { return }
      guard self.generation == gen else {
        DispatchQueue.main.async { result("failed") }
        return
      }
      do {
        try self.startEngine(recreate: true)
        DispatchQueue.main.async {
          guard self.generation == gen else {
            result("failed")
            return
          }
          self.emitCatalog()
          self.emitIsolation()
          self.emitRoute()
          result(self.startedFormatMap())
        }
      } catch {
        self.running = false
        self.teardownEngine()
        let line = "fac.audio start failed \(error)\n"
        NSLog("%@", line)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fac.audio.log")
        try? line.write(to: url, atomically: true, encoding: .utf8)
        DispatchQueue.main.async { result("failed") }
      }
    }
  }

  private func stopNative(result: FlutterResult?) {
    running = false
    generation += 1
    audioQueue.async { [weak self] in
      self?.teardownEngine()
      if let result {
        DispatchQueue.main.async { result(nil) }
      }
    }
  }

  private func resumeEngine(result: @escaping FlutterResult) {
    audioQueue.async { [weak self] in
      guard let self, let engine = self.engine else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      var thrown: NSError?
      var swiftError: Error?
      let ok = FacTry({
        do {
          try engine.start()
        } catch {
          swiftError = error
        }
      }, &thrown)
      if let swiftError {
        NSLog("fac.audio resume failed \(swiftError)")
      } else if !ok {
        NSLog("fac.audio resume NSException \(thrown?.localizedDescription ?? "")")
      }
      DispatchQueue.main.async { result(nil) }
    }
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

  /// Fieldist `configureGraph`: stop before reset, 1ch tap before start, no
  /// `player.play()` here. Recreate only when the graph is cold or in-place
  /// configure fails.
  private func startEngine(recreate: Bool) throws {
    guard !isRebuildingGraph else { return }
    isRebuildingGraph = true
    defer { isRebuildingGraph = false }

    let wantCapture = wantsCapture()
    let wantPlayback = wantsPlayback()
    if wantCapture {
      emitSilenceFrame()
    }

    stopGraph()

    var next: AVAudioEngine
    if recreate || engine == nil {
      engine?.reset()
      next = AVAudioEngine()
      engine = next
      player = nil
      playbackFormat = nil
      playbackConverter = nil
      captureConverter = nil
      captureConverterFromRate = 0
      captureConverterToRate = 0
    } else {
      next = engine!
    }

    bindDevice(to: next.inputNode, endpointId: selectedCaptureId)
    bindDevice(to: next.outputNode, endpointId: selectedRenderId)

    if wantPlayback {
      let node: AVAudioPlayerNode
      if let existing = player, next.attachedNodes.contains(existing) {
        node = existing
      } else {
        node = AVAudioPlayerNode()
        next.attach(node)
        player = node
      }
      next.disconnectNodeOutput(node)
      next.connect(node, to: next.mainMixerNode, format: nil)
    }
    next.connect(next.mainMixerNode, to: next.outputNode, format: nil)

    if wantCapture {
      applyVoiceProcessing(on: next)
    }
    if wantPlayback, let node = player {
      let hardware = next.outputNode.inputFormat(forBus: 0)
      if hardware.sampleRate > 0, hardware.channelCount > 0 {
        next.disconnectNodeOutput(node)
        next.connect(node, to: next.mainMixerNode, format: hardware)
        next.connect(next.mainMixerNode, to: next.outputNode, format: nil)
        playbackFormat = hardware
        if let source = AVAudioFormat(
          commonFormat: .pcmFormatInt16,
          sampleRate: edgeSampleRate,
          channels: 1,
          interleaved: true
        ) {
          playbackConverter = AVAudioConverter(from: source, to: hardware)
        }
      }
    }

    if wantCapture {
      try installCaptureTap(on: next.inputNode)
    }
    next.prepare()
    do {
      try startEngineGraph(next)
    } catch {
      NSLog("fac.audio startEngineGraph failed \(error)")
      abandonEngine(next)
      throw error
    }
    // start() restores the default output; rebind so the selected Endpoint sticks.
    let boundOutput = bindDevice(to: next.outputNode, endpointId: selectedRenderId)
    let boundInput: String?
    if presentId(selectedCaptureId) != nil {
      boundInput = bindDevice(to: next.inputNode, endpointId: selectedCaptureId)
    } else {
      boundInput = nil
    }
    if postStartBindFailed(selectedId: selectedRenderId, boundUid: boundOutput)
      || postStartBindFailed(selectedId: selectedCaptureId, boundUid: boundInput)
    {
      NSLog(
        "fac.audio post-start bind failed capture=%@/%@ render=%@/%@",
        selectedCaptureId ?? "",
        boundInput ?? "nil",
        selectedRenderId ?? "",
        boundOutput ?? "nil"
      )
      abandonEngine(next)
      throw MacAudioEngineError.routeFailed
    }
    queuedPlaybackFrames = 0
    scheduledPlaybackBuffers = 0
    NSLog(
      "fac.audio graph running capture=%@/%@ render=%@/%@ vp=%d",
      selectedCaptureId ?? "",
      boundInput ?? "",
      selectedRenderId ?? "",
      boundOutput ?? "",
      voiceProcessingEnabled ? 1 : 0
    )
  }

  /// A selected Endpoint whose post-start bind returned nil must fail
  /// start/select. Nil selected is OS default and may stay unbound (#95).
  private func postStartBindFailed(selectedId: String?, boundUid: String?) -> Bool {
    presentId(selectedId) != nil && boundUid == nil
  }

  private func abandonEngine(_ next: AVAudioEngine) {
    stopGraph()
    next.reset()
    engine = nil
    player = nil
    playbackFormat = nil
    playbackConverter = nil
    captureConverter = nil
    captureConverterFromRate = 0
    captureConverterToRate = 0
  }

  /// Fieldist `endSession` / `configureGraph` order: tap off, VP off,
  /// player.stop, engine.stop. `reset()` only after stop, never on a live graph.
  private func stopGraph() {
    guard let engine else { return }
    if captureTapInstalled {
      engine.inputNode.removeTap(onBus: 0)
      captureTapInstalled = false
    }
    if voiceProcessingEnabled || engine.inputNode.isVoiceProcessingEnabled {
      try? engine.inputNode.setVoiceProcessingEnabled(false)
    }
    voiceProcessingEnabled = false
    player?.stop()
    var thrown: NSError?
    _ = FacTry({
      if engine.isRunning {
        engine.stop()
      }
    }, &thrown)
    captureTapFrames = 0
    scheduledPlaybackBuffers = 0
  }

  private func teardownEngine() {
    stopGraph()
    engine?.reset()
    engine = nil
    player = nil
    playbackFormat = nil
    playbackConverter = nil
    captureConverter = nil
    captureConverterFromRate = 0
    captureConverterToRate = 0
    captureTapInstalled = false
    captureTapFrames = 0
    scheduledPlaybackBuffers = 0
    voiceProcessingEnabled = false
  }

  /// Voice Processing on a USB composite (BRIO mic+camera) resets the
  /// UVC function: AVCaptureSession starts, then AVErrorDeviceWasDisconnected.
  private func applyVoiceProcessing(on engine: AVAudioEngine) {
    let captureIsBuiltIn =
      selectedCaptureId?.localizedCaseInsensitiveContains("BuiltIn") == true
    guard noiseCancelling, captureIsBuiltIn else {
      if engine.inputNode.isVoiceProcessingEnabled {
        try? engine.inputNode.setVoiceProcessingEnabled(false)
      }
      voiceProcessingEnabled = false
      return
    }
    do {
      try engine.inputNode.setVoiceProcessingEnabled(true)
      if engine.inputNode.isVoiceProcessingBypassed {
        engine.inputNode.isVoiceProcessingBypassed = false
      }
      voiceProcessingEnabled = engine.inputNode.isVoiceProcessingEnabled
    } catch {
      voiceProcessingEnabled = false
      NSLog("fac.audio VoiceProcessingIO failed %@", error.localizedDescription)
    }
  }

  /// `installTap` and `start()` throw NSException (-10868) on Join. Swift `do` cannot catch that.
  private func startEngineGraph(_ engine: AVAudioEngine) throws {
    var thrown: NSError?
    var swiftError: Error?
    let ok = FacTry({
      do {
        try engine.start()
      } catch {
        swiftError = error
      }
    }, &thrown)
    if let swiftError {
      throw swiftError
    }
    if !ok {
      throw thrown ?? NSError(
        domain: "fac.audio",
        code: -10868,
        userInfo: [NSLocalizedDescriptionKey: "AVAudioEngine.start NSException"]
      )
    }
  }

  private func installCaptureTap(on node: AVAudioInputNode) throws {
    guard !captureTapInstalled else {
      return
    }
    let processed = node.outputFormat(forBus: 0)
    // Fieldist: 1ch tap only. A stereo fallback here is what Join logged as
    // rate=44100 ch=2 then -10868 on engine.start().
    let oneChannel = captureTapFormat(
      inputFormat: processed,
      channels: min(Int(processed.channelCount), 1)
    )
    let handler: (AVAudioPCMBuffer, AVAudioTime) -> Void = { [weak self] buffer, _ in
      self?.emitCapture(buffer)
    }
    let candidates: [AVAudioFormat?] = [oneChannel, nil]
    for tapFormat in candidates {
      var thrown: NSError?
      let ok = FacTry({
        node.installTap(onBus: 0, bufferSize: 1024, format: tapFormat, block: handler)
      }, &thrown)
      if ok {
        captureTapInstalled = true
        NSLog(
          "fac.audio tap installed rate=%.0f ch=%u",
          tapFormat?.sampleRate ?? processed.sampleRate,
          tapFormat?.channelCount ?? processed.channelCount
        )
        return
      }
    }
    NSLog("fac.audio tap skipped")
    throw NSError(
      domain: "fac.audio",
      code: -10868,
      userInfo: [NSLocalizedDescriptionKey: "capture tap failed"]
    )
  }

  private func captureTapFormat(inputFormat: AVAudioFormat, channels: Int) -> AVAudioFormat? {
    guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
      return nil
    }
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
      map["nativeCaptureFormat"] = formatMap(sampleRate: edgeSampleRate)
    }
    if wantsPlayback() {
      map["nativePlaybackFormat"] = formatMap(sampleRate: edgeSampleRate)
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

  private func emitCapture(_ buffer: AVAudioPCMBuffer) {
    if paused || !running { return }
    guard let pcm16 = pcm16MonoData(from: buffer) else { return }
    guard let hub = resamplePcm16Mono(
      pcm16,
      fromRate: buffer.format.sampleRate,
      toRate: edgeSampleRate
    ) else { return }
    emitCaptureBytes(FlutterStandardTypedData(bytes: hub))
    captureTapFrames += 1
    if captureTapFrames == 1 || captureTapFrames % 50 == 0 {
      NSLog(
        "fac.audio tap frames=%d bytes=%d sink=%d",
        captureTapFrames,
        hub.count,
        captureSink == nil ? 0 : 1
      )
    }
  }

  private func pcm16MonoData(from buffer: AVAudioPCMBuffer) -> Data? {
    let frameCount = Int(buffer.frameLength)
    guard frameCount > 0 else { return nil }
    let planarOrMono = !buffer.format.isInterleaved || buffer.format.channelCount <= 1
    if planarOrMono, let int16 = buffer.int16ChannelData?[0] {
      return Data(bytes: int16, count: frameCount * MemoryLayout<Int16>.size)
    }
    if planarOrMono, let floats = buffer.floatChannelData?[0] {
      var bytes = [UInt8](repeating: 0, count: frameCount * 2)
      for index in 0..<frameCount {
        writeInt16(int16Sample(floats: floats[index]), into: &bytes, at: index)
      }
      return Data(bytes)
    }
    let abl = buffer.audioBufferList.pointee
    guard abl.mNumberBuffers > 0, let mData = abl.mBuffers.mData else { return nil }
    let channels = max(Int(buffer.format.channelCount), 1)
    let interleaved = buffer.format.isInterleaved
    if buffer.format.commonFormat == .pcmFormatInt16 {
      let src = mData.assumingMemoryBound(to: Int16.self)
      if interleaved, channels > 1 {
        var bytes = [UInt8](repeating: 0, count: frameCount * 2)
        for index in 0..<frameCount {
          writeInt16(src[index * channels], into: &bytes, at: index)
        }
        return Data(bytes)
      }
      return Data(bytes: src, count: frameCount * MemoryLayout<Int16>.size)
    }
    if buffer.format.commonFormat == .pcmFormatFloat32 {
      let src = mData.assumingMemoryBound(to: Float.self)
      var bytes = [UInt8](repeating: 0, count: frameCount * 2)
      for index in 0..<frameCount {
        let sample = interleaved && channels > 1 ? src[index * channels] : src[index]
        writeInt16(int16Sample(floats: sample), into: &bytes, at: index)
      }
      return Data(bytes)
    }
    return nil
  }

  private func resamplePcm16Mono(_ data: Data, fromRate: Double, toRate: Double) -> Data? {
    guard fromRate > 0, toRate > 0 else { return nil }
    if abs(fromRate - toRate) < 0.5 {
      return data
    }
    guard let sourceFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: fromRate,
      channels: 1,
      interleaved: false
    ),
    let destinationFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: toRate,
      channels: 1,
      interleaved: false
    )
    else { return nil }
    let converter: AVAudioConverter
    if let existing = captureConverter,
       abs(captureConverterFromRate - fromRate) < 0.5,
       abs(captureConverterToRate - toRate) < 0.5
    {
      converter = existing
    } else if let created = AVAudioConverter(from: sourceFormat, to: destinationFormat) {
      captureConverter = created
      captureConverterFromRate = fromRate
      captureConverterToRate = toRate
      converter = created
    } else {
      return nil
    }
    let sourceFrames = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
    guard let sourceBuffer = AVAudioPCMBuffer(
      pcmFormat: sourceFormat,
      frameCapacity: sourceFrames
    ) else { return nil }
    sourceBuffer.frameLength = sourceFrames
    data.withUnsafeBytes { raw in
      if let src = raw.bindMemory(to: Int16.self).baseAddress,
         let dst = sourceBuffer.int16ChannelData?[0]
      {
        dst.update(from: src, count: Int(sourceFrames))
      }
    }
    let capacity = AVAudioFrameCount(
      (Double(sourceFrames) * toRate / fromRate).rounded(.up)
    ) + 32
    guard let destinationBuffer = AVAudioPCMBuffer(
      pcmFormat: destinationFormat,
      frameCapacity: capacity
    ) else { return nil }
    var suppliedInput = false
    var conversionError: NSError?
    converter.convert(to: destinationBuffer, error: &conversionError) { _, status in
      if suppliedInput {
        status.pointee = .noDataNow
        return nil
      }
      suppliedInput = true
      status.pointee = .haveData
      return sourceBuffer
    }
    guard conversionError == nil,
          destinationBuffer.frameLength > 0,
          let samples = destinationBuffer.int16ChannelData?[0]
    else { return nil }
    return Data(
      bytes: samples,
      count: Int(destinationBuffer.frameLength) * MemoryLayout<Int16>.size
    )
  }

  private func int16Sample(floats value: Float) -> Int16 {
    let clamped = max(-1.0, min(1.0, Double(value)))
    return Int16((clamped * 32767.0).rounded())
  }

  private func writeInt16(_ sample: Int16, into bytes: inout [UInt8], at index: Int) {
    bytes[index * 2] = UInt8(truncatingIfNeeded: sample)
    bytes[index * 2 + 1] = UInt8(truncatingIfNeeded: sample >> 8)
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
    guard let data, let player, running, !paused, !isRebuildingGraph else { return }
    guard engine?.isRunning == true else { return }
    guard scheduledPlaybackBuffers < maxScheduledPlaybackBuffers else { return }
    guard let destinationFormat = playbackFormat, let playbackConverter else { return }
    guard let sourceFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: edgeSampleRate,
      channels: 1,
      interleaved: true
    ) else { return }
    let frameCount = AVAudioFrameCount(data.data.count / MemoryLayout<Int16>.size)
    guard frameCount > 0,
          let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount)
    else { return }
    inputBuffer.frameLength = frameCount
    data.data.withUnsafeBytes { raw in
      if let source = raw.baseAddress, let destination = inputBuffer.int16ChannelData?[0] {
        memcpy(destination, source, data.data.count)
      }
    }
    let capacity = AVAudioFrameCount(
      (Double(frameCount) * destinationFormat.sampleRate / edgeSampleRate).rounded(.up)
    ) + 16
    guard let outputBuffer = AVAudioPCMBuffer(
      pcmFormat: destinationFormat,
      frameCapacity: capacity
    ) else { return }
    var consumed = false
    var conversionError: NSError?
    playbackConverter.convert(to: outputBuffer, error: &conversionError) { _, status in
      if consumed {
        status.pointee = .noDataNow
        return nil
      }
      consumed = true
      status.pointee = .haveData
      return inputBuffer
    }
    guard conversionError == nil, outputBuffer.frameLength > 0 else { return }
    scheduledPlaybackBuffers += 1
    player.scheduleBuffer(outputBuffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
      self?.audioQueue.async {
        guard let self else { return }
        self.scheduledPlaybackBuffers = max(0, self.scheduledPlaybackBuffers - 1)
      }
    }
    // Fieldist: player.play() on the method-channel thread after an IO cycle.
    // Calling it during configureGraph throws "player did not see an IO cycle".
    if !player.isPlaying {
      var thrown: NSError?
      _ = FacTry({
        player.play()
      }, &thrown)
    }
  }

  private func flushPlayback() {
    player?.stop()
    queuedPlaybackFrames = 0
    scheduledPlaybackBuffers = 0
  }

  private func selectEndpoints(
    captureId: String?,
    renderId: String?,
    result: @escaping FlutterResult
  ) {
    let sameCapture = captureId == nil || captureId == selectedCaptureId
    let sameRender = renderId == nil || renderId == selectedRenderId
    if running, sameCapture, sameRender {
      result(startedFormatMap())
      return
    }
    if let captureId { selectedCaptureId = captureId }
    if let renderId { selectedRenderId = renderId }
    guard running else {
      result(startedFormatMap())
      return
    }
    let recreate = engine == nil
    audioQueue.async { [weak self] in
      guard let self else { return }
      do {
        try self.startEngine(recreate: recreate)
      } catch {
        if !recreate {
          do {
            try self.startEngine(recreate: true)
          } catch {
            DispatchQueue.main.async {
              self.emitPath(alive: false)
              result(Self.routeFailedError)
            }
            return
          }
        } else {
          DispatchQueue.main.async {
            self.emitPath(alive: false)
            result(Self.routeFailedError)
          }
          return
        }
      }
      DispatchQueue.main.async {
        self.emitRoute()
        self.emitIsolation()
        result(self.startedFormatMap())
      }
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
      let hidden = boolProperty(id, kAudioDevicePropertyIsHidden)
      if !includeInCatalog(name: name, transport: transport, hidden: hidden) {
        continue
      }
      let route = routeClass(name: name, transport: transport)
      let pairId = pairIdentity(
        route: route,
        uid: uid,
        name: name,
        transport: transport,
        deviceID: id
      )
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
      "osDefault": NSNumber(value: osDefault),
      "capabilities": [
        "formFactor": "unknown",
        "aec": false,
        "ns": false,
        "agc": false,
        "carConnected": false,
      ],
    ]
  }

  /// Returns the Core Audio UID that was bound, or nil if unbound / unresolved.
  @discardableResult
  private func bindDevice(to node: AVAudioNode, endpointId: String?) -> String? {
    guard let endpointId else {
      return nil
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
      NSLog("MacOSAudioEngine deviceID(forUID:) failed uid=%@", uid)
      return nil
    }
    node.auAudioUnit.setValue(NSNumber(value: deviceID), forKey: "deviceID")
    return uid
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

  private func includeInCatalog(name: String, transport: String, hidden: Bool) -> Bool {
    if hidden {
      return false
    }
    let t = transport.lowercased()
    if t == "virt" || t == "grup" || t == "auto" || t == "fgrp" {
      return false
    }
    let n = name.lowercased()
    let blocked = [
      "microsoft teams audio",
      "caddefaultdeviceaggregate",
      "zoomaudio",
      "blackhole",
      "soundflower",
      "vb-audio",
      "multi-output device",
    ]
    for needle in blocked where n.contains(needle) {
      return false
    }
    if n.contains("loopback") {
      return false
    }
    return true
  }

  private func boolProperty(
    _ id: AudioDeviceID,
    _ selector: AudioObjectPropertySelector
  ) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else {
      return false
    }
    return value != 0
  }

  private func routeClass(name: String, transport: String) -> String {
    let n = name.lowercased()
    let t = transport.lowercased()
    if t.contains("blue") || t.contains("blea") || n.contains("bluetooth") {
      return "bluetooth"
    }
    if n.contains("headset") ||
      n.contains("headphone") ||
      n.contains("earphone") ||
      t.contains("usb")
    {
      return "wired"
    }
    // Built-in from transport only — do not classify from display-name words (issue #90).
    if t.contains("bltn") || t.contains("pci") {
      return "speakerphone"
    }
    return "wired"
  }

  /// Pair key from Core Audio hardware metadata (issue #90).
  private func pairIdentity(route: String, uid: String, name _: String, transport: String, deviceID: AudioDeviceID) -> String {
    let t = transport.lowercased()
    if t.contains("bltn") || t.contains("pci") || (t.isEmpty && route == "speakerphone") {
      return "built-in"
    }
    if t.contains("blue") || t.contains("blea") {
      if uid.hasSuffix(":input") {
        return String(uid.dropLast(":input".count))
      }
      if uid.hasSuffix(":output") {
        return String(uid.dropLast(":output".count))
      }
      return uid
    }
    var clique = relatedDeviceUIDs(deviceID)
    clique.insert(uid)
    return clique.sorted().joined(separator: "|")
  }

  /// `kAudioDevicePropertyRelatedDevices` clique UIDs.
  private func relatedDeviceUIDs(_ deviceID: AudioDeviceID) -> Set<String> {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyRelatedDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
      dataSize > 0
    else {
      return []
    }
    let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var relatedIDs = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &relatedIDs) == noErr
    else {
      return []
    }
    var uids = Set<String>()
    for relatedID in relatedIDs {
      if let relatedUID = stringProperty(relatedID, kAudioDevicePropertyDeviceUID) {
        uids.insert(relatedUID)
      }
    }
    return uids
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
