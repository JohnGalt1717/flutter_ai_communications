import AppKit
import CoreGraphics
import FlutterMacOS
import Foundation
import ScreenCaptureKit

/// ScreenCaptureKit Production video path, Screen pick thumbs, and Share frame.
///
/// Host picker, not `SCContentSharingPicker`. Camera graph is a separate path.
final class MacScreenGraph: NSObject, SCStreamOutput, SCStreamDelegate {
  private let queue = DispatchQueue(label: "fac.screen")
  private weak var textures: FlutterTextureRegistry?
  private var emitCatalog: (([[String: Any]]) -> Void)?
  private let production = ProductionTexture()
  private(set) var textureId: Int64 = -1
  private var pixelBuffer: CVPixelBuffer?
  private var stitchBuffer: CVPixelBuffer?
  private let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

  private var content: SCShareableContent?
  private var streams: [SCStream] = []
  private var streamRects: [ObjectIdentifier: CGRect] = [:]
  private var sendWidth = 1280
  private var sendHeight = 720
  private var frameRate = 5
  private var includeAudio = false
  private var cursor = true
  private var motion = false
  private var sendId: String?
  private var indicatedId: String?

  private var overlayWindows: [NSWindow] = []
  private var followTimer: Timer?
  private var previews: [String: PreviewTexture] = [:]

  func attach(textures: FlutterTextureRegistry) {
    self.textures = textures
    production.graph = self
  }

  func attachCatalog(_ emit: @escaping ([[String: Any]]) -> Void) {
    emitCatalog = emit
  }

  func copySendBuffer() -> Unmanaged<CVPixelBuffer>? {
    guard let buffer = pixelBuffer ?? stitchBuffer else {
      return nil
    }
    return Unmanaged.passRetained(buffer)
  }

  private func ensureProductionTexture() {
    guard textureId < 0, let textures else {
      return
    }
    textureId = textures.register(production)
  }

  func enumerate(result: @escaping FlutterResult) {
    refreshContent { [weak self] content, error in
      guard let self else {
        result([])
        return
      }
      if Self.isDenied(error) {
        result([])
        return
      }
      result(self.sourceMaps(from: content))
    }
  }

  func requestPermission(result: @escaping FlutterResult) {
    if CGPreflightScreenCaptureAccess() {
      result("granted")
      return
    }
    let granted = CGRequestScreenCaptureAccess()
    result(granted ? "granted" : "denied")
  }

  func beginPick(result: @escaping FlutterResult) {
    endPick()
    refreshContent { [weak self] content, _ in
      guard let self, let content else {
        result(["previews": [:] as [String: Int64]])
        return
      }
      Task {
        let maps = await self.capturePreviews(content: content)
        self.mainAsync {
          result(["previews": maps])
        }
      }
    }
  }

  func endPick() {
    for preview in previews.values {
      if preview.textureId >= 0 {
        textures?.unregisterTexture(preview.textureId)
      }
    }
    previews.removeAll()
    if sendId == nil {
      hideFrame()
    }
  }

  func indicate(sourceId: String?) {
    indicatedId = sourceId
    guard let sourceId, !sourceId.isEmpty else {
      if sendId == nil {
        hideFrame()
      } else {
        showFrame(for: sendId)
      }
      return
    }
    showFrame(for: sourceId)
  }

  func start(
    sourceId: String,
    includeSystemAudio: Bool,
    cursor: Bool,
    motion: Bool,
    result: @escaping FlutterResult
  ) {
    stopStreams()
    includeAudio = includeSystemAudio
    self.cursor = cursor
    self.motion = motion
    frameRate = motion ? 30 : 5
    sendId = sourceId
    refreshContent { [weak self] content, error in
      guard let self else {
        result(["status": "failed", "reason": "none"])
        return
      }
      if Self.isDenied(error) {
        result(["status": "unavailable", "reason": "denied"])
        return
      }
      guard let content else {
        result(["status": "unavailable", "reason": "none"])
        return
      }
      self.content = content
      self.ensureProductionTexture()
      self.queue.async {
        do {
          try self.startLocked(sourceId: sourceId, content: content)
          self.mainAsync {
            self.showFrame(for: sourceId)
            result(
              [
                "status": "started",
                "textureId": Int(self.textureId),
                "width": self.sendWidth,
                "height": self.sendHeight,
                "frameRate": self.frameRate,
                "kind": "texture",
              ]
            )
          }
        } catch {
          self.mainAsync {
            self.sendId = nil
            if Self.isDenied(error) {
              result(["status": "unavailable", "reason": "denied"])
            } else {
              result(["status": "failed", "reason": "none"])
            }
          }
        }
      }
    }
  }

  func stop() {
    sendId = nil
    includeAudio = false
    stopStreams()
    hideFrame()
    pixelBuffer = nil
    stitchBuffer = nil
  }

  func setIncludeSystemAudio(_ enabled: Bool) -> Bool {
    guard #available(macOS 13.0, *) else {
      return false
    }
    includeAudio = enabled
    applyConfiguration()
    return enabled
  }

  func setMotion(_ motion: Bool) {
    self.motion = motion
    frameRate = motion ? 30 : 5
    applyConfiguration()
  }

  func setCursor(_ cursor: Bool) {
    self.cursor = cursor
    applyConfiguration()
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .screen, let image = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return
    }
    if streams.count <= 1 {
      pixelBuffer = copyBuffer(image)
    } else if let dest = stitchBuffer, let rect = streamRects[ObjectIdentifier(stream)] {
      blit(image, into: dest, dest: rect)
      pixelBuffer = dest
    } else {
      pixelBuffer = copyBuffer(image)
    }
    textures?.textureFrameAvailable(textureId)
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    mainAsync { [weak self] in
      guard let self else {
        return
      }
      let gone = self.sendId
      guard gone != nil else {
        return
      }
      self.stop()
      var sources = self.sourceMaps(from: self.content)
      if let gone {
        sources.removeAll { ($0["id"] as? String) == gone }
      }
      self.emitCatalog?(sources)
    }
  }

  private func startLocked(sourceId: String, content: SCShareableContent) throws {
    let ownApps = content.applications.filter {
      $0.bundleIdentifier == Bundle.main.bundleIdentifier
    }
    if sourceId == "all-displays" {
      try startAllDisplays(content: content, excluding: ownApps)
      return
    }
    if sourceId.hasPrefix("display-"), let displayID = UInt32(sourceId.dropFirst("display-".count)),
       let display = content.displays.first(where: { $0.displayID == displayID })
    {
      let size = cappedSize(width: Int(display.width), height: Int(display.height))
      sendWidth = size.0
      sendHeight = size.1
      let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
      try addStream(filter: filter, width: sendWidth, height: sendHeight, rect: nil)
      return
    }
    if sourceId.hasPrefix("window-"), let windowID = UInt32(sourceId.dropFirst("window-".count)),
       let window = content.windows.first(where: { $0.windowID == windowID })
    {
      let frame = window.frame
      let size = cappedSize(width: Int(frame.width.rounded()), height: Int(frame.height.rounded()))
      sendWidth = size.0
      sendHeight = size.1
      let filter = SCContentFilter(desktopIndependentWindow: window)
      try addStream(filter: filter, width: sendWidth, height: sendHeight, rect: nil)
      return
    }
    throw NSError(domain: "fac.screen", code: 1)
  }

  private func startAllDisplays(content: SCShareableContent, excluding apps: [SCRunningApplication]) throws {
    let displays = content.displays
    guard !displays.isEmpty else {
      throw NSError(domain: "fac.screen", code: 2)
    }
    let union = displays.map(\.frame).reduce(CGRect.null) { $0.union($1) }
    let size = cappedSize(width: Int(union.width.rounded()), height: Int(union.height.rounded()))
    sendWidth = size.0
    sendHeight = size.1
    stitchBuffer = makeBuffer(width: sendWidth, height: sendHeight)
    pixelBuffer = stitchBuffer
    let scaleX = union.width > 0 ? CGFloat(sendWidth) / union.width : 1
    let scaleY = union.height > 0 ? CGFloat(sendHeight) / union.height : 1
    for display in displays {
      let filter = SCContentFilter(display: display, excludingApplications: apps, exceptingWindows: [])
      let local = CGRect(
        x: (display.frame.minX - union.minX) * scaleX,
        y: (union.maxY - display.frame.maxY) * scaleY,
        width: display.frame.width * scaleX,
        height: display.frame.height * scaleY
      )
      let streamSize = cappedSize(
        width: Int(display.frame.width.rounded()),
        height: Int(display.frame.height.rounded())
      )
      try addStream(filter: filter, width: streamSize.0, height: streamSize.1, rect: local)
    }
  }

  private func addStream(filter: SCContentFilter, width: Int, height: Int, rect: CGRect?) throws {
    let config = makeConfiguration(width: width, height: height)
    let stream = SCStream(filter: filter, configuration: config, delegate: self)
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
    if #available(macOS 13.0, *), includeAudio {
      try? stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
    }
    let started = DispatchSemaphore(value: 0)
    var startError: Error?
    stream.startCapture { error in
      startError = error
      started.signal()
    }
    started.wait()
    if let startError {
      throw startError
    }
    streams.append(stream)
    if let rect {
      streamRects[ObjectIdentifier(stream)] = rect
    }
  }

  private func makeConfiguration(width: Int, height: Int) -> SCStreamConfiguration {
    let config = SCStreamConfiguration()
    config.width = width
    config.height = height
    config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
    config.queueDepth = 3
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.showsCursor = cursor
    if #available(macOS 13.0, *) {
      config.capturesAudio = includeAudio
      config.excludesCurrentProcessAudio = true
    }
    return config
  }

  private func applyConfiguration() {
    let config = makeConfiguration(width: sendWidth, height: sendHeight)
    for stream in streams {
      stream.updateConfiguration(config) { _ in }
    }
  }

  private func stopStreams() {
    let live = streams
    streams = []
    streamRects.removeAll()
    let group = DispatchGroup()
    for stream in live {
      group.enter()
      stream.stopCapture { _ in
        group.leave()
      }
    }
    _ = group.wait(timeout: .now() + 2)
  }

  private func refreshContent(_ completion: @escaping (SCShareableContent?, Error?) -> Void) {
    SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
      self.mainAsync {
        if let content {
          self.content = content
        }
        completion(content, error)
      }
    }
  }

  private func sourceMaps(from content: SCShareableContent?) -> [[String: Any]] {
    guard let content else {
      return []
    }
    var items: [[String: Any]] = []
    var union = CGRect.null
    for display in content.displays {
      union = union.union(display.frame)
      items.append(
        sourceMap(
          id: "display-\(display.displayID)",
          name: displayName(display),
          kind: "display",
          frame: display.frame,
          canPreview: true
        )
      )
    }
    if !content.displays.isEmpty {
      items.append(
        sourceMap(
          id: "all-displays",
          name: "All displays",
          kind: "allDisplays",
          frame: union,
          canPreview: true
        )
      )
    }
    let overlayIds = Set(overlayWindows.map { CGWindowID($0.windowNumber) })
    let cg = Self.cgWindowMeta()
    for window in content.windows {
      guard Self.shouldPublish(window, overlayIds: overlayIds, cg: cg) else {
        continue
      }
      items.append(
        sourceMap(
          id: "window-\(window.windowID)",
          name: window.title ?? "",
          kind: "window",
          frame: window.frame,
          canPreview: true,
          applicationName: window.owningApplication?.applicationName
        )
      )
    }
    return items
  }

  private func sourceMap(
    id: String,
    name: String,
    kind: String,
    frame: CGRect,
    canPreview: Bool,
    applicationName: String? = nil
  ) -> [String: Any] {
    var map: [String: Any] = [
      "id": id,
      "name": name,
      "kind": kind,
      "x": Int(frame.minX.rounded()),
      "y": Int(frame.minY.rounded()),
      "width": Int(frame.width.rounded()),
      "height": Int(frame.height.rounded()),
      "canPreview": canPreview,
    ]
    if let applicationName, !applicationName.isEmpty {
      map["applicationName"] = applicationName
    }
    return map
  }

  private static func shouldPublish(
    _ window: SCWindow,
    overlayIds: Set<CGWindowID>,
    cg: [CGWindowID: CGWindowMeta]
  ) -> Bool {
    if overlayIds.contains(window.windowID) {
      return false
    }
    let meta = cg[window.windowID]
    return shouldIncludeWindow(
      title: window.title,
      layer: window.windowLayer,
      isOnScreen: window.isOnScreen && (meta?.onScreen ?? true),
      width: window.frame.width,
      height: window.frame.height,
      appName: window.owningApplication?.applicationName,
      alpha: meta?.alpha ?? 1,
      sharingState: meta?.sharingState ?? 2
    )
  }

  /// Off-screen, transparent, non-shareable, tiny, and non-normal-layer
  /// windows (menus, HUD, Stage Manager strips) are omitted. Cocoa's
  /// default title "Window" is not a shareable source. Empty titles are
  /// kept only when the owning app is known so Dart can label them.
  static func shouldIncludeWindow(
    title: String?,
    layer: Int,
    isOnScreen: Bool,
    width: CGFloat,
    height: CGFloat,
    appName: String?,
    alpha: Double = 1,
    sharingState: Int = 2
  ) -> Bool {
    if !isOnScreen || layer != 0 || width < 64 || height < 64 {
      return false
    }
    if alpha < 0.05 || sharingState == 0 {
      return false
    }
    let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if trimmed.caseInsensitiveCompare("Window") == .orderedSame {
      return false
    }
    let app = appName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return !trimmed.isEmpty || !app.isEmpty
  }

  private struct CGWindowMeta {
    var alpha: Double
    var onScreen: Bool
    var sharingState: Int
  }

  private static func cgWindowMeta() -> [CGWindowID: CGWindowMeta] {
    guard let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]
    else {
      return [:]
    }
    var map: [CGWindowID: CGWindowMeta] = [:]
    for item in info {
      guard let number = item[kCGWindowNumber as String] as? NSNumber else {
        continue
      }
      map[CGWindowID(truncating: number)] = CGWindowMeta(
        alpha: (item[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
        onScreen: (item[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false,
        sharingState: (item[kCGWindowSharingState as String] as? NSNumber)?.intValue ?? 2
      )
    }
    return map
  }

  private func displayName(_ display: SCDisplay) -> String {
    let screen = NSScreen.screens.first { screen in
      let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
      return number?.uint32Value == display.displayID
    }
    return screen?.localizedName ?? "Display \(display.displayID)"
  }

  private func capturePreviews(content: SCShareableContent) async -> [String: Int64] {
    var maps: [String: Int64] = [:]
    let ownApps = content.applications.filter {
      $0.bundleIdentifier == Bundle.main.bundleIdentifier
    }
    for display in content.displays {
      let id = "display-\(display.displayID)"
      let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
      if let texture = await previewTexture(id: id, filter: filter, frame: display.frame) {
        maps[id] = texture.textureId
      }
    }
    if !content.displays.isEmpty {
      let union = content.displays.map(\.frame).reduce(CGRect.null) { $0.union($1) }
      if let first = content.displays.first {
        let filter = SCContentFilter(display: first, excludingApplications: ownApps, exceptingWindows: [])
        if let texture = await previewTexture(id: "all-displays", filter: filter, frame: union) {
          maps["all-displays"] = texture.textureId
        }
      }
    }
    let overlayIds = Set(overlayWindows.map { CGWindowID($0.windowNumber) })
    let cg = Self.cgWindowMeta()
    for window in content.windows.prefix(48) {
      guard Self.shouldPublish(window, overlayIds: overlayIds, cg: cg) else {
        continue
      }
      let id = "window-\(window.windowID)"
      let filter = SCContentFilter(desktopIndependentWindow: window)
      if let texture = await previewTexture(id: id, filter: filter, frame: window.frame) {
        maps[id] = texture.textureId
      }
    }
    return maps
  }

  private func previewTexture(id: String, filter: SCContentFilter, frame: CGRect) async -> PreviewTexture? {
    let image = await screenshot(filter: filter, frame: frame)
    guard let image else {
      return nil
    }
    return await MainActor.run {
      let preview = PreviewTexture()
      preview.pixelBuffer = self.pixelBuffer(from: image, width: 160, height: 90)
      if let textures {
        preview.textureId = textures.register(preview)
        textures.textureFrameAvailable(preview.textureId)
      }
      self.previews[id] = preview
      return preview
    }
  }

  private func screenshot(filter: SCContentFilter, frame: CGRect) async -> CGImage? {
    if #available(macOS 14.0, *) {
      let config = SCStreamConfiguration()
      let size = cappedSize(width: 160, height: max(Int((160.0 * frame.height / max(frame.width, 1)).rounded()), 1))
      config.width = size.0
      config.height = size.1
      config.showsCursor = false
      config.pixelFormat = kCVPixelFormatType_32BGRA
      return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
    let rect = CGRect(x: frame.minX, y: frame.minY, width: max(frame.width, 1), height: max(frame.height, 1))
    return CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.boundsIgnoreFraming])
  }

  private func showFrame(for sourceId: String?) {
    hideFrame()
    guard let sourceId, let content else {
      return
    }
    let frames: [CGRect]
    if sourceId == "all-displays" {
      frames = content.displays.map(\.frame)
    } else if sourceId.hasPrefix("display-"), let displayID = UInt32(sourceId.dropFirst("display-".count)),
              let display = content.displays.first(where: { $0.displayID == displayID })
    {
      frames = [display.frame]
    } else if sourceId.hasPrefix("window-"), let windowID = UInt32(sourceId.dropFirst("window-".count)),
              let window = content.windows.first(where: { $0.windowID == windowID })
    {
      frames = [window.frame]
    } else {
      frames = []
    }
    for frame in frames where frame.width > 2 && frame.height > 2 {
      overlayWindows.append(ShareFrameWindow(frame: frame))
    }
    followTimer?.invalidate()
    followTimer = nil
    if sourceId.hasPrefix("window-") {
      followTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
        self?.repositionWindowFrame(sourceId)
      }
    }
  }

  private func repositionWindowFrame(_ sourceId: String) {
    guard sourceId.hasPrefix("window-"),
          let windowID = UInt32(sourceId.dropFirst("window-".count)),
          let window = content?.windows.first(where: { $0.windowID == windowID }),
          let overlay = overlayWindows.first
    else {
      return
    }
    overlay.setFrame(window.frame, display: true)
  }

  private func hideFrame() {
    followTimer?.invalidate()
    followTimer = nil
    for window in overlayWindows {
      window.orderOut(nil)
    }
    overlayWindows.removeAll()
  }

  private func blit(_ src: CVPixelBuffer, into dst: CVPixelBuffer, dest: CGRect) {
    let image = CIImage(cvPixelBuffer: src)
    let sx = dest.width / max(image.extent.width, 1)
    let sy = dest.height / max(image.extent.height, 1)
    let transform = CGAffineTransform(translationX: dest.minX, y: dest.minY)
      .scaledBy(x: sx, y: sy)
      .translatedBy(x: -image.extent.minX, y: -image.extent.minY)
    let transformed = image.transformed(by: transform)
    ciContext.render(
      transformed,
      to: dst,
      bounds: dest,
      colorSpace: CGColorSpaceCreateDeviceRGB()
    )
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

  private func pixelBuffer(from image: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
    guard let buffer = makeBuffer(width: width, height: height) else {
      return nil
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else {
      return buffer
    }
    let context = CGContext(
      data: base,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    )
    context?.interpolationQuality = .low
    context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return buffer
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

  private func cappedSize(width: Int, height: Int) -> (Int, Int) {
    let w = max(width, 1)
    let h = max(height, 1)
    if w <= 1920 && h <= 1080 {
      return (w, h)
    }
    let scale = min(1920.0 / Double(w), 1080.0 / Double(h))
    return (max(Int((Double(w) * scale).rounded()), 1), max(Int((Double(h) * scale).rounded()), 1))
  }

  private func mainAsync(_ body: @escaping () -> Void) {
    if Thread.isMainThread {
      body()
    } else {
      DispatchQueue.main.async(execute: body)
    }
  }

  private static func isDenied(_ error: Error?) -> Bool {
    guard let error = error as NSError? else {
      return false
    }
    if error.domain == SCStreamErrorDomain && error.code == SCStreamError.userDeclined.rawValue {
      return true
    }
    return error.domain == NSOSStatusErrorDomain && error.code == -1751
  }
}

private final class ProductionTexture: NSObject, FlutterTexture {
  weak var graph: MacScreenGraph?

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    graph?.copySendBuffer()
  }
}

private final class PreviewTexture: NSObject, FlutterTexture {
  var pixelBuffer: CVPixelBuffer?
  var textureId: Int64 = -1

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    guard let pixelBuffer else {
      return nil
    }
    return Unmanaged.passRetained(pixelBuffer)
  }
}

private final class ShareFrameWindow: NSWindow {
  convenience init(frame: CGRect) {
    self.init(
      contentRect: frame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    ignoresMouseEvents = true
    level = .statusBar
    collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    sharingType = .none
    isExcludedFromWindowsMenu = true
    title = ""
    contentView = ShareFrameView(frame: NSRect(origin: .zero, size: frame.size))
    setFrame(frame, display: true)
    orderFrontRegardless()
  }
}

private final class ShareFrameView: NSView {
  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.red.setStroke()
    let path = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
    path.lineWidth = 4
    path.stroke()
  }
}
