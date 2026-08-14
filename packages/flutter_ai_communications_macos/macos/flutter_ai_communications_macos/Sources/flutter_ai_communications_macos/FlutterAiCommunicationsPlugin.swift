import AVFoundation
import CoreAudio
import FlutterMacOS

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
  private var listeningForDevices = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FlutterAiCommunicationsPlugin()
    let messenger = registrar.messenger
    let methods = FlutterMethodChannel(name: instance.methods, binaryMessenger: messenger)
    registrar.addMethodCallDelegate(instance, channel: methods)
    FlutterEventChannel(name: instance.captureName, binaryMessenger: messenger)
      .setStreamHandler(CaptureHandler(plugin: instance))
    FlutterEventChannel(name: instance.eventsName, binaryMessenger: messenger)
      .setStreamHandler(EventHandler(plugin: instance))
    instance.listenForDeviceChanges()
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
    if sink != nil {
      emitCatalog()
      emitIsolation()
    }
  }

  private func requestPermission(result: @escaping FlutterResult) {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      result("granted")
    case .denied:
      result("denied")
    case .restricted:
      result("restricted")
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        result(granted ? "granted" : "denied")
      }
    @unknown default:
      result("denied")
    }
  }

  private func startNative(captureId: String?, renderId: String?, result: @escaping FlutterResult) {
    selectedCaptureId = captureId
    selectedRenderId = renderId
    do {
      try startEngine()
      running = true
      paused = false
      emitCatalog()
      emitIsolation()
      emitRoute()
      emitPath(alive: true)
      result("started")
    } catch {
      result("failed")
    }
  }

  private func stopNative() {
    running = false
    NotificationCenter.default.removeObserver(self)
    engine?.inputNode.removeTap(onBus: 0)
    engine?.stop()
    player?.stop()
    engine = nil
    player = nil
  }

  private func startEngine() throws {
    emitSilenceFrame()
    engine?.inputNode.removeTap(onBus: 0)
    engine?.stop()
    NotificationCenter.default.removeObserver(self)
    let next = AVAudioEngine()
    let playerNode = AVAudioPlayerNode()
    next.attach(playerNode)
    applyDevices(to: next)
    let format = next.inputNode.outputFormat(forBus: 0)
    next.connect(playerNode, to: next.mainMixerNode, format: format)
    next.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      self?.emitCapture(buffer)
    }
    try next.start()
    engine = next
    player = playerNode
    playerNode.play()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleEngineConfigChange),
      name: .AVAudioEngineConfigurationChange,
      object: next
    )
  }

  private func applyDevices(to engine: AVAudioEngine) {
    if let selectedCaptureId, let device = deviceID(uid: selectedCaptureId) {
      setDevice(device, on: engine.inputNode)
    }
    if let selectedRenderId, let device = deviceID(uid: selectedRenderId) {
      setDevice(device, on: engine.outputNode)
    }
  }

  private func setDevice(_ deviceID: AudioDeviceID, on node: AVAudioIONode) {
    guard let audioUnit = node.audioUnit else { return }
    var id = deviceID
    AudioUnitSetProperty(
      audioUnit,
      kAudioOutputUnitProperty_CurrentDevice,
      kAudioUnitScope_Global,
      0,
      &id,
      UInt32(MemoryLayout<AudioDeviceID>.size)
    )
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
    do {
      try startEngine()
      emitRoute()
      emitPath(alive: true)
    } catch {
      emitPath(alive: false)
    }
  }

  private func enumerateEndpoints() -> [[String: Any]] {
    var items: [[String: Any]] = []
    for id in allDeviceIDs() {
      guard let uid = copyString(id, kAudioDevicePropertyDeviceUID) else { continue }
      let name = copyString(id, kAudioObjectPropertyName) ?? uid
      let route = routeClass(for: transportType(id))
      let pairId = pairId(for: id, uid: uid, name: name, route: route)
      if channelCount(id, scope: kAudioObjectPropertyScopeInput) > 0 {
        items.append(endpoint(uid, name, route, true, pairId))
      }
      if channelCount(id, scope: kAudioObjectPropertyScopeOutput) > 0 {
        items.append(endpoint(uid, name, route, false, pairId))
      }
    }
    return items
  }

  private func pairId(for id: AudioDeviceID, uid: String, name: String, route: String) -> String {
    if route == "speakerphone" {
      return "built-in"
    }
    if let model = copyString(id, kAudioDevicePropertyModelUID), !model.isEmpty {
      return model
    }
    return name.isEmpty ? uid : name
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

  private func routeClass(for transport: UInt32) -> String {
    switch transport {
    case kAudioDeviceTransportTypeBuiltIn:
      return "speakerphone"
    case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
      return "bluetooth"
    default:
      return "wired"
    }
  }

  private func emitCatalog() {
    eventSink?(["type": "catalog", "payload": enumerateEndpoints()])
  }

  private func emitIsolation() {
    eventSink?(["type": "isolation", "payload": "unavailable"])
  }

  private func openIsolationSettings() {
    emitIsolation()
  }

  private func emitPath(alive: Bool) {
    let reason: Any = alive ? NSNull() : "pathDead"
    eventSink?(
      [
        "type": "path",
        "payload": ["alive": alive, "reason": reason],
      ]
    )
  }

  private func emitRoute() {
    eventSink?(
      [
        "type": "route",
        "payload": [
          "captureId": selectedCaptureId as Any,
          "renderId": selectedRenderId as Any,
        ],
      ]
    )
  }

  @objc private func handleEngineConfigChange(_ notification: Notification) {
    emitCatalog()
    emitRoute()
    guard running else { return }
    do {
      try startEngine()
      emitPath(alive: true)
    } catch {
      emitPath(alive: false)
    }
  }

  private func listenForDeviceChanges() {
    if listeningForDevices { return }
    listeningForDevices = true
    let system = AudioObjectID(kAudioObjectSystemObject)
    addListener(system, kAudioHardwarePropertyDevices) { [weak self] in
      self?.emitCatalog()
    }
    addListener(system, kAudioHardwarePropertyDefaultInputDevice) { [weak self] in
      self?.emitCatalog()
      self?.emitRoute()
    }
    addListener(system, kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
      self?.emitCatalog()
      self?.emitRoute()
    }
  }

  private func addListener(
    _ object: AudioObjectID,
    _ selector: AudioObjectPropertySelector,
    handler: @escaping () -> Void
  ) {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: 0
    )
    AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main) { _, _ in
      handler()
    }
  }

  private func allDeviceIDs() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: 0
    )
    let system = AudioObjectID(kAudioObjectSystemObject)
    var dataSize: UInt32 = 0
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

  private func deviceID(uid: String) -> AudioDeviceID? {
    allDeviceIDs().first { copyString($0, kAudioDevicePropertyDeviceUID) == uid }
  }

  private func copyString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: 0
    )
    var dataSize = UInt32(MemoryLayout<CFString?>.size)
    var cfString: CFString?
    let status = withUnsafeMutablePointer(to: &cfString) { pointer in
      AudioObjectGetPropertyData(object, &address, 0, nil, &dataSize, pointer)
    }
    guard status == noErr else { return nil }
    return cfString as String?
  }

  private func transportType(_ id: AudioDeviceID) -> UInt32 {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: 0
    )
    var value = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
    return value
  }

  private func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamConfiguration,
      mScope: scope,
      mElement: 0
    )
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
      return 0
    }
    let raw = UnsafeMutableRawPointer.allocate(
      byteCount: Int(dataSize),
      alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, raw) == noErr else {
      return 0
    }
    let list = raw.assumingMemoryBound(to: AudioBufferList.self)
    let buffers = UnsafeMutableAudioBufferListPointer(list)
    return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
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
