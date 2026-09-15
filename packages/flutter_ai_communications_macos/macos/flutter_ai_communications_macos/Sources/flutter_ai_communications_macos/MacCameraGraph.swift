import AVFoundation
import CoreImage
import CoreVideo
import FlutterMacOS
import Foundation
import VideoToolbox

final class MacCameraGraph: NSObject, FlutterTexture, AVCaptureVideoDataOutputSampleBufferDelegate {
  private var session = AVCaptureSession()
  private var output = AVCaptureVideoDataOutput()
  /// Session start/stop/config. Must not be the sample-buffer queue:
  /// `startRunning` blocks and will starve `captureOutput` if they share it.
  private let sessionQueue = DispatchQueue(label: "fac.camera.session")
  private let queue = DispatchQueue(label: "fac.camera.frames")
  private var device: AVCaptureDevice?
  private var input: AVCaptureDeviceInput?
  private var pixelBuffer: CVPixelBuffer?
  private var blackBuffer: CVPixelBuffer?
  private weak var textures: FlutterTextureRegistry?
  private(set) var textureId: Int64 = -1
  var muted = false
  var enabled = true
  private let processor = PersonBackgroundProcessor()
  private let renderContext = CIContext(options: [
    .cacheIntermediates: false,
    .workingColorSpace: NSNull(),
  ])
  private var transfer: VTPixelTransferSession?
  private(set) var width = 1280
  private(set) var height = 720
  private(set) var frameRate = 30
  private var frameCount = 0
  private var liveFrames = 0
  private let bufferLock = NSLock()
  private var sessionObservers: [NSObjectProtocol] = []
  // Flutter macOS compositor only samples IOSurface-backed 32BGRA. Empty
  // IOSurface property dict must be a CFDictionary (String:Any does not
  // create an IOSurface and Texture stays black).
  private let bufferAttrs: [CFString: Any] = [
    kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
    kCVPixelBufferMetalCompatibilityKey: true,
  ]

  func attach(textures: FlutterTextureRegistry) {
    self.textures = textures
  }

  private func ensureTexture() {
    guard textureId < 0, let textures else {
      return
    }
    textureId = textures.register(self)
    NSLog("fac.camera registered textureId=%lld", textureId)
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    bufferLock.lock()
    let buffer = muted ? blackBuffer : (pixelBuffer ?? blackBuffer)
    bufferLock.unlock()
    guard let buffer else {
      return nil
    }
    return Unmanaged.passRetained(buffer)
  }

  func enumerate() -> [[String: Any]] {
    return videoDevices().map { device in
      [
        "id": device.uniqueID,
        "name": device.localizedName,
        "facing": facingName(for: device),
        "modes": [["width": 1280, "height": 720, "frameRate": 30]],
      ]
    }
  }

  func requestPermission(result: @escaping FlutterResult) {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      result("granted")
    case .denied:
      result("denied")
    case .restricted:
      result("restricted")
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async {
          result(granted ? "granted" : "denied")
        }
      }
    @unknown default:
      result("denied")
    }
  }

  func start(cameraId: String?, width: Int, height: Int, enabled: Bool, muted: Bool) -> [String: Any] {
    guard textures != nil else {
      return ["status": "failed"]
    }
    ensureTexture()
    self.enabled = enabled
    self.muted = muted
    self.width = width
    self.height = height
    frameCount = 0
    liveFrames = 0
    makeBlackBuffer(width: width, height: height)
    setLiveBuffer(blackBuffer)
    publishTexture()
    guard enabled else {
      sessionQueue.async { [weak self] in
        self?.stopLocked()
      }
      setLiveBuffer(blackBuffer)
      publishTexture()
      return ["status": "started", "textureId": textureId, "width": width, "height": height, "frameRate": frameRate]
    }
    let devices = videoDevices()
    let chosen =
      devices.first(where: { $0.uniqueID == cameraId })
      ?? devices.first(where: { $0.position == .front })
      ?? devices.first
    guard let chosen else {
      return ["status": "unavailable"]
    }
    // camera_desktop: setup + startRunning on a session queue, never the
    // method-channel/main thread. startRunning is blocking; on USB DAL it
    // needs the main run loop, so calling it here wedges captureOutput.
    // camera_macos only looks like it runs on main — it actually starts
    // inside requestAccess's off-main completion.
    camLog("open queued device=\(chosen.localizedName) id=\(chosen.uniqueID)")
    sessionQueue.async { [weak self] in
      self?.openLocked(chosen)
    }
    return [
      "status": "started",
      "textureId": textureId,
      "width": width,
      "height": height,
      "frameRate": frameRate,
    ]
  }

  func select(cameraId: String) {
    _ = start(cameraId: cameraId, width: width, height: height, enabled: enabled, muted: muted)
  }

  func setEnabled(_ enabled: Bool) {
    self.enabled = enabled
    sessionQueue.async { [weak self] in
      guard let self else {
        return
      }
      if enabled {
        if !self.session.isRunning {
          self.session.startRunning()
        }
      } else {
        if self.session.isRunning {
          self.session.stopRunning()
        }
        self.setLiveBuffer(nil)
      }
    }
  }

  func setMuted(_ muted: Bool) {
    self.muted = muted
    publishTexture()
  }

  func setProcessor(_ args: [String: Any]) -> String {
    processor.apply(args)
  }

  func stats() -> [String: Any] {
    ["frameCount": frameCount, "liveFrames": liveFrames]
  }

  func stop() {
    sessionQueue.async { [weak self] in
      self?.stopLocked()
    }
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didDrop sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    camLog("dropped frames=\(frameCount)")
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    frameArrived(sampleBuffer)
  }

  func frameArrived(_ sampleBuffer: CMSampleBuffer) {
    let image = CMSampleBufferGetImageBuffer(sampleBuffer)
    if image == nil {
      camLog("didOutput without imageBuffer")
    }
    guard enabled, let image else {
      return
    }
    frameCount += 1
    let format = CVPixelBufferGetPixelFormatType(image)
    let hasIOSurface = CVPixelBufferGetIOSurface(image) != nil
    let formatOK =
      format == kCVPixelFormatType_32BGRA
      || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
      || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    // Flutter macOS compositor only wraps IOSurface-backed 32BGRA / NV12.
    let delivered: CVPixelBuffer? = formatOK && hasIOSurface ? image : copyBuffer(image)
    let processed = delivered.map { processor.process($0) } ?? delivered
    setLiveBuffer(processed)
    if !muted {
      liveFrames += 1
    }
    if frameCount == 1 || frameCount % 30 == 0 {
      let fourcc = CVPixelBufferGetPixelFormatType(image)
      let iosurface = processed.flatMap { CVPixelBufferGetIOSurface($0) } != nil
      camLog(
        "frames=\(frameCount) live=\(liveFrames) src=0x\(String(fourcc, radix: 16)) dstIOSurface=\(iosurface) w=\(CVPixelBufferGetWidth(image)) h=\(CVPixelBufferGetHeight(image)) delivered=\(delivered != nil)"
      )
    }
    publishTexture()
  }

  private func observeSession() {
    guard sessionObservers.isEmpty else {
      return
    }
    let center = NotificationCenter.default
    sessionObservers.append(
      center.addObserver(
        forName: .AVCaptureSessionRuntimeError,
        object: session,
        queue: nil
      ) { [weak self] note in
        let error = note.userInfo?[AVCaptureSessionErrorKey]
        self?.camLog("runtimeError \(String(describing: error))")
      }
    )
    sessionObservers.append(
      center.addObserver(
        forName: .AVCaptureSessionDidStartRunning,
        object: session,
        queue: nil
      ) { [weak self] _ in
        self?.camLog("didStartRunning")
      }
    )
  }

  private func camLog(_ message: String) {
    let line = "fac.camera \(message)"
    NSLog("%@", line)
    let dir = FileManager.default.temporaryDirectory
    let url = dir.appendingPathComponent("fac.camera.log")
    guard let data = (line + "\n").data(using: .utf8) else {
      return
    }
    if FileManager.default.fileExists(atPath: url.path) {
      if let handle = try? FileHandle(forWritingTo: url) {
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.close()
      }
    } else {
      try? data.write(to: url)
    }
  }

  private func applyUpright(_ connection: AVCaptureConnection, for device: AVCaptureDevice) {
    if #available(macOS 14.0, *) {
      if connection.isVideoRotationAngleSupported(0) {
        connection.videoRotationAngle = 0
      }
    }
    if connection.isVideoMirroringSupported {
      connection.automaticallyAdjustsVideoMirroring = false
      connection.isVideoMirrored = device.position == .front
    }
  }

  private func videoDeviceTypes() -> [AVCaptureDevice.DeviceType] {
    var types: [AVCaptureDevice.DeviceType] = [
      .builtInWideAngleCamera,
      .externalUnknown,
    ]
    if #available(macOS 13.0, *) {
      types.append(.deskViewCamera)
    }
    if #available(macOS 14.0, *) {
      types.append(.continuityCamera)
      types.append(.external)
    }
    return types
  }

  private func videoDevices() -> [AVCaptureDevice] {
    AVCaptureDevice.DiscoverySession(
      deviceTypes: videoDeviceTypes(),
      mediaType: .video,
      position: .unspecified
    ).devices
  }

  private func facingName(for device: AVCaptureDevice) -> String {
    switch device.position {
    case .front:
      return "user"
    case .back:
      return "environment"
    default:
      let haystack = device.localizedName.lowercased()
      let userMarks = [
        "macbook", "imac", "facetime", "built-in", "studio display",
        "continuity", "front", "user",
      ]
      if userMarks.contains(where: { haystack.contains($0) }) {
        return "user"
      }
      if haystack.contains("rear") || haystack.contains("back") {
        return "environment"
      }
      return "external"
    }
  }

  private func publishTexture() {
    guard textureId >= 0 else {
      return
    }
    if Thread.isMainThread {
      textures?.textureFrameAvailable(textureId)
      return
    }
    DispatchQueue.main.async { [weak self] in
      guard let self, self.textureId >= 0 else {
        return
      }
      self.textures?.textureFrameAvailable(self.textureId)
    }
  }

  private func openLocked(_ chosen: AVCaptureDevice) {
    stopLocked()
    resetSession()
    // camera_desktop locks for focus/exposure on built-in cameras. On USB
    // composites (BRIO) this lock can hang forever if AVAudioEngine already
    // holds the audio function, so skip it unless the device is built-in.
    if chosen.position == .front || chosen.position == .back {
      do {
        try chosen.lockForConfiguration()
        if chosen.isFocusModeSupported(.continuousAutoFocus) {
          chosen.focusMode = .continuousAutoFocus
        }
        if chosen.isExposureModeSupported(.continuousAutoExposure) {
          chosen.exposureMode = .continuousAutoExposure
        }
        chosen.unlockForConfiguration()
      } catch {
        camLog("lockForConfiguration skipped \(error)")
      }
    }
    do {
      let input = try AVCaptureDeviceInput(device: chosen)
      session.beginConfiguration()
      let preset: AVCaptureSession.Preset =
        chosen.supportsSessionPreset(.hd1280x720) && session.canSetSessionPreset(.hd1280x720)
        ? .hd1280x720
        : chosen.supportsSessionPreset(.high) && session.canSetSessionPreset(.high)
          ? .high
          : .medium
      if session.canSetSessionPreset(preset) {
        session.sessionPreset = preset
      }
      guard session.canAddInput(input) else {
        session.commitConfiguration()
        camLog("canAddInput=false device=\(chosen.localizedName)")
        return
      }
      session.addInput(input)
      output.alwaysDiscardsLateVideoFrames = true
      output.setSampleBufferDelegate(self, queue: .main)
      guard session.canAddOutput(output) else {
        session.removeInput(input)
        session.commitConfiguration()
        camLog("canAddOutput=false")
        return
      }
      session.addOutput(output)
      applyPixelFormat(output)
      if let connection = output.connection(with: .video) {
        applyUpright(connection, for: chosen)
      }
      session.commitConfiguration()
      device = chosen
      self.input = input
      camLog("configured device=\(chosen.localizedName) id=\(chosen.uniqueID) preset=\(preset.rawValue)")
      observeSession()
      session.startRunning()
      let connection = output.connection(with: .video)
      camLog(
        "running=\(session.isRunning) inputs=\(session.inputs.count) outputs=\(session.outputs.count) textureId=\(textureId) connEnabled=\(connection?.isEnabled == true) connActive=\(connection?.isActive == true) delegate=\(output.sampleBufferDelegate != nil)"
      )
      let expectedId = chosen.uniqueID
      sessionQueue.asyncAfter(deadline: .now() + 2) { [weak self] in
        guard let self, self.device?.uniqueID == expectedId else {
          return
        }
        self.retryNativeFormatIfSilent()
      }
    } catch {
      camLog("configure failed \(error)")
    }
  }

  private func retryNativeFormatIfSilent() {
    guard frameCount == 0, session.isRunning, session.outputs.contains(output) else {
      return
    }
    camLog("no frames after 2s, bouncing session with device-native pixel format")
    session.stopRunning()
    session.beginConfiguration()
    output.videoSettings = [:]
    session.commitConfiguration()
    session.startRunning()
    let connection = output.connection(with: .video)
    camLog(
      "native-format retry running=\(session.isRunning) connActive=\(connection?.isActive == true) settings=\(String(describing: output.videoSettings))"
    )
  }

  private func applyPixelFormat(_ output: AVCaptureVideoDataOutput) {
    // camera_macos / camera_desktop request 32BGRA. On BRIO that produced a
    // running session and zero callbacks; retryNativeFormatIfSilent then
    // bounces to device-native (`2vuy`) after stop/start.
    output.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]
  }





  private func resetSession() {
    for observer in sessionObservers {
      NotificationCenter.default.removeObserver(observer)
    }
    sessionObservers.removeAll()
    session = AVCaptureSession()
    output = AVCaptureVideoDataOutput()
  }

  private func stopLocked() {
    output.setSampleBufferDelegate(nil, queue: nil)
    if session.isRunning {
      session.stopRunning()
    }
    session.beginConfiguration()
    if let input {
      session.removeInput(input)
    }
    if session.outputs.contains(output) {
      session.removeOutput(output)
    }
    session.commitConfiguration()
    input = nil
    device = nil
    setLiveBuffer(nil)
  }

  private func setLiveBuffer(_ buffer: CVPixelBuffer?) {
    bufferLock.lock()
    pixelBuffer = buffer
    bufferLock.unlock()
  }

  private func copyBuffer(_ src: CVPixelBuffer) -> CVPixelBuffer? {
    let width = CVPixelBufferGetWidth(src)
    let height = CVPixelBufferGetHeight(src)
    var dst: CVPixelBuffer?
    CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      bufferAttrs as CFDictionary,
      &dst
    )
    guard let dst else {
      return nil
    }
    if transfer == nil {
      VTPixelTransferSessionCreate(
        allocator: kCFAllocatorDefault,
        pixelTransferSessionOut: &transfer
      )
    }
    if let transfer,
       VTPixelTransferSessionTransferImage(transfer, from: src, to: dst) == noErr
    {
      return dst
    }
    // CI's origin is bottom-left; flip so Flutter Texture is upright.
    let image = CIImage(cvPixelBuffer: src).oriented(.downMirrored)
    let space = CGColorSpaceCreateDeviceRGB()
    renderContext.render(image, to: dst, bounds: image.extent, colorSpace: space)
    return dst
  }

  private func makeBlackBuffer(width: Int, height: Int) {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      bufferAttrs as CFDictionary,
      &buffer
    )
    if let buffer {
      CVPixelBufferLockBaseAddress(buffer, [])
      if let base = CVPixelBufferGetBaseAddress(buffer) {
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for row in 0..<height {
          memset(base + row * stride, 0, stride)
        }
      }
      CVPixelBufferUnlockBaseAddress(buffer, [])
      NSLog(
        "fac.camera seed iosurface=%d textureId=%lld",
        CVPixelBufferGetIOSurface(buffer) != nil,
        textureId
      )
    }
    blackBuffer = buffer
  }
}
