import AVFoundation
import Flutter
import Foundation

final class IosCameraGraph: NSObject, FlutterTexture, AVCaptureVideoDataOutputSampleBufferDelegate {
  private let session = AVCaptureSession()
  private let output = AVCaptureVideoDataOutput()
  private let queue = DispatchQueue(label: "fac.camera")
  private var device: AVCaptureDevice?
  private var input: AVCaptureDeviceInput?
  private var pixelBuffer: CVPixelBuffer?
  private var blackBuffer: CVPixelBuffer?
  private weak var textures: FlutterTextureRegistry?
  private(set) var textureId: Int64 = -1
  var muted = false
  var enabled = true
  private(set) var width = 1280
  private(set) var height = 720
  private(set) var frameRate = 30

  func attach(textures: FlutterTextureRegistry) {
    self.textures = textures
    if textureId < 0 {
      textureId = textures.register(self)
    }
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    let buffer = muted ? blackBuffer : pixelBuffer
    guard let buffer else {
      return nil
    }
    return Unmanaged.passRetained(buffer)
  }

  func enumerate() -> [[String: Any]] {
    let discovery = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera, .builtInTelephotoCamera, .builtInUltraWideCamera],
      mediaType: .video,
      position: .unspecified
    )
    return discovery.devices.map { device in
      let facing: String
      switch device.position {
      case .front: facing = "user"
      case .back: facing = "environment"
      default: facing = "unspecified"
      }
      return [
        "id": device.uniqueID,
        "name": device.localizedName,
        "facing": facing,
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
    self.enabled = enabled
    self.muted = muted
    self.width = width
    self.height = height
    makeBlackBuffer(width: width, height: height)
    guard enabled else {
      queue.sync { stopLocked() }
      return ["status": "started", "textureId": textureId, "width": width, "height": height, "frameRate": frameRate]
    }
    let devices = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera, .builtInTelephotoCamera, .builtInUltraWideCamera],
      mediaType: .video,
      position: .unspecified
    ).devices
    let chosen =
      devices.first(where: { $0.uniqueID == cameraId })
      ?? devices.first(where: { $0.position == .front })
      ?? devices.first
    guard let chosen else {
      return ["status": "unavailable"]
    }
    var status = "failed"
    queue.sync {
      stopLocked()
      do {
        let input = try AVCaptureDeviceInput(device: chosen)
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        if session.canAddInput(input) {
          session.addInput(input)
        }
        output.videoSettings = [
          kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) {
          session.addOutput(output)
        }
        session.commitConfiguration()
        device = chosen
        self.input = input
        status = "started"
      } catch {
        status = "failed"
      }
    }
    if status == "started" {
      queue.async { [weak self] in
        self?.session.startRunning()
      }
    }
    return [
      "status": status,
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
    queue.async { [weak self] in
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
        self.pixelBuffer = nil
      }
    }
  }

  func setMuted(_ muted: Bool) {
    self.muted = muted
    textures?.textureFrameAvailable(textureId)
  }

  func stop() {
    queue.sync { stopLocked() }
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard enabled, let image = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return
    }
    pixelBuffer = copyBuffer(image)
    textures?.textureFrameAvailable(textureId)
  }

  private func stopLocked() {
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
    pixelBuffer = nil
  }

  private func copyBuffer(_ src: CVPixelBuffer) -> CVPixelBuffer? {
    var dst: CVPixelBuffer?
    let attrs: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
    ]
    CVPixelBufferCreate(
      kCFAllocatorDefault,
      CVPixelBufferGetWidth(src),
      CVPixelBufferGetHeight(src),
      CVPixelBufferGetPixelFormatType(src),
      attrs as CFDictionary,
      &dst
    )
    guard let dst else {
      return nil
    }
    copyPlanes(from: src, to: dst)
    return dst
  }

  private func copyPlanes(from src: CVPixelBuffer, to dst: CVPixelBuffer) {
    CVPixelBufferLockBaseAddress(src, .readOnly)
    CVPixelBufferLockBaseAddress(dst, [])
    let planes = max(CVPixelBufferGetPlaneCount(src), 1)
    if CVPixelBufferGetPlaneCount(src) == 0 {
      copyPlane(from: src, to: dst, plane: nil)
    } else {
      for plane in 0..<planes {
        copyPlane(from: src, to: dst, plane: plane)
      }
    }
    CVPixelBufferUnlockBaseAddress(dst, [])
    CVPixelBufferUnlockBaseAddress(src, .readOnly)
  }

  private func copyPlane(from src: CVPixelBuffer, to dst: CVPixelBuffer, plane: Int?) {
    let srcBase: UnsafeMutableRawPointer?
    let dstBase: UnsafeMutableRawPointer?
    let height: Int
    let srcStride: Int
    let dstStride: Int
    let width: Int
    if let plane {
      srcBase = CVPixelBufferGetBaseAddressOfPlane(src, plane)
      dstBase = CVPixelBufferGetBaseAddressOfPlane(dst, plane)
      height = CVPixelBufferGetHeightOfPlane(src, plane)
      width = CVPixelBufferGetWidthOfPlane(src, plane)
      srcStride = CVPixelBufferGetBytesPerRowOfPlane(src, plane)
      dstStride = CVPixelBufferGetBytesPerRowOfPlane(dst, plane)
    } else {
      srcBase = CVPixelBufferGetBaseAddress(src)
      dstBase = CVPixelBufferGetBaseAddress(dst)
      height = CVPixelBufferGetHeight(src)
      width = CVPixelBufferGetWidth(src)
      srcStride = CVPixelBufferGetBytesPerRow(src)
      dstStride = CVPixelBufferGetBytesPerRow(dst)
    }
    guard let srcBase, let dstBase else {
      return
    }
    let rowBytes = min(srcStride, dstStride, max(width, 1) * 4)
    for row in 0..<height {
      memcpy(dstBase + row * dstStride, srcBase + row * srcStride, rowBytes)
    }
  }

  private func makeBlackBuffer(width: Int, height: Int) {
    var buffer: CVPixelBuffer?
    let attrs: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
    ]
    CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      attrs as CFDictionary,
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
    }
    blackBuffer = buffer
  }
}
