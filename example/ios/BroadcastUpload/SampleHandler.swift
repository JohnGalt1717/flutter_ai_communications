import CoreImage
import CoreMedia
import ReplayKit

/// Host Broadcast upload extension. Writes BGRA frames into the App Group
/// for the Communications plugin Texture. Not a library target.
final class SampleHandler: RPBroadcastSampleHandler {
  private let group = "group.com.example.flutterAiCommunications"
  private let startedName = CFNotificationName("com.johngalt.fac.screen.started" as CFString)
  private let finishedName = CFNotificationName("com.johngalt.fac.screen.finished" as CFString)
  private let stopName = "com.johngalt.fac.screen.stop" as CFString
  private let ci = CIContext(options: [.workingColorSpace: NSNull()])
  private var seq: UInt32 = 0
  private var lastWrite = CFAbsoluteTimeGetCurrent()
  private var stopObserver: UnsafeRawPointer?

  override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
    observeStop()
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      startedName,
      nil,
      nil,
      true
    )
  }

  override func broadcastFinished() {
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      finishedName,
      nil,
      nil,
      true
    )
  }

  override func processSampleBuffer(
    _ sampleBuffer: CMSampleBuffer,
    with sampleBufferType: RPSampleBufferType
  ) {
    guard sampleBufferType == .video,
          let image = CMSampleBufferGetImageBuffer(sampleBuffer)
    else {
      return
    }
    let now = CFAbsoluteTimeGetCurrent()
    if now - lastWrite < 0.18 {
      return
    }
    lastWrite = now
    write(image)
  }

  private func write(_ src: CVPixelBuffer) {
    let width = CVPixelBufferGetWidth(src)
    let height = CVPixelBufferGetHeight(src)
    var bgra: CVPixelBuffer?
    let attrs: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
    ]
    CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      attrs as CFDictionary,
      &bgra
    )
    guard let bgra else {
      return
    }
    ci.render(CIImage(cvPixelBuffer: src), to: bgra)
    CVPixelBufferLockBaseAddress(bgra, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(bgra, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(bgra) else {
      return
    }
    let stride = CVPixelBufferGetBytesPerRow(bgra)
    seq &+= 1
    let rowBytes = width * 4
    var payload = Data(count: 16 + rowBytes * height)
    payload.withUnsafeMutableBytes { raw in
      guard let dest = raw.baseAddress else {
        return
      }
      dest.storeBytes(of: UInt32(0xFAC5_C0DE), as: UInt32.self)
      dest.advanced(by: 4).storeBytes(of: UInt32(width), as: UInt32.self)
      dest.advanced(by: 8).storeBytes(of: UInt32(height), as: UInt32.self)
      dest.advanced(by: 12).storeBytes(of: seq, as: UInt32.self)
      for row in 0..<height {
        memcpy(dest.advanced(by: 16 + row * rowBytes), base + row * stride, rowBytes)
      }
    }
    guard let url = FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: group)?
      .appendingPathComponent("fac-screen.raw")
    else {
      return
    }
    try? payload.write(to: url, options: .atomic)
  }

  private func observeStop() {
    let pointer = Unmanaged.passUnretained(self).toOpaque()
    stopObserver = UnsafeRawPointer(pointer)
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      pointer,
      { _, observer, _, _, _ in
        guard let observer else {
          return
        }
        let handler = Unmanaged<SampleHandler>.fromOpaque(observer).takeUnretainedValue()
        let error = NSError(
          domain: "com.johngalt.fac.screen",
          code: 0,
          userInfo: [NSLocalizedFailureReasonErrorKey: "stop"]
        )
        handler.finishBroadcastWithError(error)
      },
      stopName,
      nil,
      .deliverImmediately
    )
  }
}
