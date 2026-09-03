import CoreMedia
import Flutter
import Foundation
import ReplayKit
import UIKit

/// iOS screen send. Catalog is one system-picker source. Production is
/// ReplayKit Broadcast → Texture. Thumbs and Share frame are no-ops.
/// In-app `RPScreenRecorder` is not full-device share.
///
/// The host ships the Broadcast upload extension and App Group. Keys in the
/// host Info.plist: `FacScreenShareExtension`, `FacScreenShareAppGroup`.
final class IosScreenGraph: NSObject, FlutterTexture {
  static let startedName = "com.johngalt.fac.screen.started" as CFString
  static let finishedName = "com.johngalt.fac.screen.finished" as CFString
  static let stopName = "com.johngalt.fac.screen.stop" as CFString

  private let queue = DispatchQueue(label: "fac.screen")
  private weak var textures: FlutterTextureRegistry?
  var onCatalog: (([[String: Any]]) -> Void)?
  private(set) var textureId: Int64 = -1
  private var pixelBuffer: CVPixelBuffer?
  private var pending: FlutterResult?
  private var sendWidth = 1280
  private var sendHeight = 720
  private var frameRate = 5
  private var sending = false
  private var displayLink: CADisplayLink?
  private var lastSeq: UInt32 = 0
  private var darwinStarted: UnsafeRawPointer?
  private var darwinFinished: UnsafeRawPointer?

  func attach(textures: FlutterTextureRegistry) {
    self.textures = textures
    if textureId < 0 {
      textureId = textures.register(self)
    }
    observeDarwin()
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    guard let pixelBuffer else {
      return nil
    }
    return Unmanaged.passRetained(pixelBuffer)
  }

  func enumerate() -> [[String: Any]] {
    [
      [
        "id": "system-picker",
        "name": "System picker",
        "kind": "systemPicker",
        "canPreview": false,
      ],
    ]
  }

  func permission() -> String {
    "granted"
  }

  func start(
    includeSystemAudio: Bool,
    cursor: Bool,
    motion: Bool,
    result: @escaping FlutterResult
  ) {
    stopCapture(emitGone: false)
    frameRate = motion ? 30 : 5
    pending = result
    presentPicker(includeSystemAudio: includeSystemAudio)
  }

  func stop() {
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(Self.stopName),
      nil,
      nil,
      true
    )
    stopCapture(emitGone: false)
    finish(["status": "unavailable", "reason": "none"])
  }

  func setIncludeSystemAudio(_ enabled: Bool) -> Bool {
    false
  }

  func setMotion(_ motion: Bool) {
    frameRate = motion ? 30 : 5
    displayLink?.preferredFramesPerSecond = frameRate
  }

  func setCursor(_ cursor: Bool) {}

  private func presentPicker(includeSystemAudio: Bool) {
    let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
    picker.preferredExtension = Bundle.main.object(forInfoDictionaryKey: "FacScreenShareExtension") as? String
    picker.showsMicrophoneButton = includeSystemAudio
    guard let window = Self.keyWindow() else {
      finish(["status": "unavailable", "reason": "none"])
      return
    }
    window.addSubview(picker)
    var tapped = false
    for view in picker.subviews {
      if let button = view as? UIButton {
        button.sendActions(for: .allTouchEvents)
        tapped = true
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      picker.removeFromSuperview()
    }
    if !tapped {
      finish(["status": "unavailable", "reason": "none"])
    }
  }

  private func broadcastDidStart() {
    sending = true
    startDisplayLink()
    finish(
      [
        "status": "started",
        "textureId": textureId,
        "width": sendWidth,
        "height": sendHeight,
        "frameRate": frameRate,
        "kind": "texture",
      ]
    )
  }

  private func broadcastDidFinish() {
    let wasSending = sending
    stopCapture(emitGone: wasSending)
  }

  private func stopCapture(emitGone: Bool) {
    sending = false
    displayLink?.invalidate()
    displayLink = nil
    pixelBuffer = nil
    if emitGone {
      onCatalog?([])
    }
  }

  private func startDisplayLink() {
    displayLink?.invalidate()
    let link = CADisplayLink(target: self, selector: #selector(onTick))
    link.preferredFramesPerSecond = frameRate
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  @objc private func onTick() {
    guard sending, let url = Self.frameURL() else {
      return
    }
    queue.async { [weak self] in
      self?.readFrame(url: url)
    }
  }

  private func readFrame(url: URL) {
    guard let data = try? Data(contentsOf: url), data.count >= 16 else {
      return
    }
    let magic: UInt32 = data.withUnsafeBytes { $0.load(as: UInt32.self) }
    guard magic == 0xFAC5_C0DE else {
      return
    }
    let width = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) })
    let height = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) })
    let seq = data.withUnsafeBytes { $0.load(fromByteOffset: 12, as: UInt32.self) }
    guard seq != lastSeq, width > 0, height > 0 else {
      return
    }
    lastSeq = seq
    let pixels = data.advanced(by: 16)
    let size = cappedSize(width: width, height: height)
    sendWidth = size.0
    sendHeight = size.1
    guard let buffer = makeBuffer(width: size.0, height: size.1) else {
      return
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    if let dest = CVPixelBufferGetBaseAddress(buffer) {
      let destStride = CVPixelBufferGetBytesPerRow(buffer)
      let srcStride = width * 4
      let rowBytes = min(srcStride, destStride)
      let rows = min(height, size.1)
      pixels.withUnsafeBytes { raw in
        guard let src = raw.baseAddress else {
          return
        }
        for row in 0..<rows {
          memcpy(dest + row * destStride, src + row * srcStride, rowBytes)
        }
      }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        return
      }
      self.pixelBuffer = buffer
      self.textures?.textureFrameAvailable(self.textureId)
    }
  }

  private func finish(_ payload: [String: Any]) {
    let reply = pending
    pending = nil
    reply?(payload)
  }

  private func observeDarwin() {
    let started = Unmanaged.passUnretained(self).toOpaque()
    darwinStarted = UnsafeRawPointer(started)
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      started,
      { _, observer, _, _, _ in
        guard let observer else {
          return
        }
        let graph = Unmanaged<IosScreenGraph>.fromOpaque(observer).takeUnretainedValue()
        DispatchQueue.main.async {
          graph.broadcastDidStart()
        }
      },
      Self.startedName,
      nil,
      .deliverImmediately
    )
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      started,
      { _, observer, _, _, _ in
        guard let observer else {
          return
        }
        let graph = Unmanaged<IosScreenGraph>.fromOpaque(observer).takeUnretainedValue()
        DispatchQueue.main.async {
          graph.broadcastDidFinish()
        }
      },
      Self.finishedName,
      nil,
      .deliverImmediately
    )
  }

  private func makeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
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
    return buffer
  }

  private func cappedSize(width: Int, height: Int) -> (Int, Int) {
    let w = max(width, 1)
    let h = max(height, 1)
    if w <= 1920 && h <= 1080 {
      return (w, h)
    }
    let scale = min(1920.0 / Double(w), 1080.0 / Double(h))
    return (max(Int((Double(w) * scale).rounded()), 1), max(Int((Double(h) * scale).rounded()), 1))
  }

  private static func keyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first { $0.isKeyWindow }
  }

  static func frameURL() -> URL? {
    let group = Bundle.main.object(forInfoDictionaryKey: "FacScreenShareAppGroup") as? String
      ?? "group.com.example.flutterAiCommunications"
    return FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: group)?
      .appendingPathComponent("fac-screen.raw")
  }
}
