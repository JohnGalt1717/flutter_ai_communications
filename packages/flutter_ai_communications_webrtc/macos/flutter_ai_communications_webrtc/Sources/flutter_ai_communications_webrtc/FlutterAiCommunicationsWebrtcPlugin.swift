import CoreImage
import CoreVideo
import WebRTC
import flutter_webrtc

#if os(iOS)
  import Flutter
  import flutter_ai_communications_ios
#else
  import FlutterMacOS
  import flutter_ai_communications_macos
#endif

/// Runs a FAC Video processor on a host flutter_webrtc local video track, in
/// place (ADR-0032). The host keeps its PeerConnection, sender, and camera.
public final class FlutterAiCommunicationsWebrtcPlugin: NSObject, FlutterPlugin {
  private var processors: [String: TrackProcessor] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(
      name: "flutter_ai_communications_webrtc",
      binaryMessenger: messenger
    )
    registrar.addMethodCallDelegate(FlutterAiCommunicationsWebrtcPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "process" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let args = call.arguments as? [String: Any] ?? [:]
    result(process(args["trackId"] as? String, args["processor"] as? [String: Any] ?? [:]))
  }

  private func process(_ trackId: String?, _ args: [String: Any]) -> String {
    for id in processors.keys where localTrack(id) == nil {
      processors[id] = nil
    }
    guard let trackId, let track = localTrack(trackId) else {
      return "noTrack"
    }
    if (args["kind"] as? String ?? "none") == "none" {
      if let processor = processors.removeValue(forKey: trackId) {
        track.removeProcessing(processor)
      }
      return "ready"
    }
    let processor: TrackProcessor
    if let existing = processors[trackId] {
      processor = existing
    } else {
      processor = TrackProcessor()
      track.addProcessing(processor)
      processors[trackId] = processor
    }
    return processor.apply(args)
  }

  /// Camera tracks carry a processing adapter. A track without one (a
  /// shared or remote track) cannot be processed, so it is not a target.
  private func localTrack(_ trackId: String) -> LocalVideoTrack? {
    guard
      let track = FlutterWebRTCPlugin.sharedSingleton()?.localTracks?[trackId]
        as? LocalVideoTrack,
      track.value(forKey: "processing") != nil
    else {
      return nil
    }
    return track
  }
}

/// FAC `PersonBackgroundProcessor` on one flutter_webrtc track. Frames are
/// turned upright (segmentation expects a standing person) and leave with
/// rotation 0.
///
/// Fails closed: while blur/replace is requested and the processor is not
/// ready or hands back the input unchanged (no mask), the frame is black.
final class TrackProcessor: NSObject, ExternalVideoProcessingDelegate {
  private let processor = PersonBackgroundProcessor()
  private let lock = NSLock()
  private let context = CIContext(options: [.cacheIntermediates: false])
  private var ready = false
  private var upright: CVPixelBuffer?
  private var black: RTCMutableI420Buffer?

  func apply(_ args: [String: Any]) -> String {
    lock.lock()
    defer { lock.unlock() }
    let status = processor.apply(args)
    ready = status == "ready"
    return status
  }

  func onFrame(_ frame: RTCVideoFrame) -> RTCVideoFrame {
    lock.lock()
    defer { lock.unlock() }
    guard ready, let input = uprightBuffer(frame) else {
      return blackFrame(frame)
    }
    let output = processor.process(input)
    if output === input {
      return blackFrame(frame)
    }
    return RTCVideoFrame(
      buffer: RTCCVPixelBuffer(pixelBuffer: output),
      rotation: ._0,
      timeStampNs: frame.timeStampNs
    )
  }

  private func uprightBuffer(_ frame: RTCVideoFrame) -> CVPixelBuffer? {
    guard let source = (frame.buffer as? RTCCVPixelBuffer)?.pixelBuffer else {
      return nil
    }
    let orientation: CGImagePropertyOrientation
    switch frame.rotation {
    case ._90:
      orientation = .right
    case ._180:
      orientation = .down
    case ._270:
      orientation = .left
    default:
      return source
    }
    let oriented = CIImage(cvPixelBuffer: source).oriented(orientation)
    let extent = oriented.extent
    guard let target = reuse(&upright, Int(extent.width), Int(extent.height)) else {
      return nil
    }
    context.render(
      oriented.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)),
      to: target
    )
    return target
  }

  private func blackFrame(_ frame: RTCVideoFrame) -> RTCVideoFrame {
    let sideways = frame.rotation == ._90 || frame.rotation == ._270
    let width = sideways ? frame.height : frame.width
    let height = sideways ? frame.width : frame.height
    let buffer: RTCMutableI420Buffer
    if let cached = black, cached.width == width, cached.height == height {
      buffer = cached
    } else {
      buffer = RTCMutableI420Buffer(width: width, height: height)
      memset(buffer.mutableDataY, 16, Int(buffer.strideY * height))
      memset(buffer.mutableDataU, 128, Int(buffer.strideU * buffer.chromaHeight))
      memset(buffer.mutableDataV, 128, Int(buffer.strideV * buffer.chromaHeight))
      black = buffer
    }
    return RTCVideoFrame(buffer: buffer, rotation: ._0, timeStampNs: frame.timeStampNs)
  }

  private func reuse(_ slot: inout CVPixelBuffer?, _ width: Int, _ height: Int) -> CVPixelBuffer? {
    if let slot, CVPixelBufferGetWidth(slot) == width, CVPixelBufferGetHeight(slot) == height {
      return slot
    }
    var created: CVPixelBuffer?
    CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      [
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        kCVPixelBufferMetalCompatibilityKey: true,
      ] as CFDictionary,
      &created
    )
    slot = created
    return created
  }
}
