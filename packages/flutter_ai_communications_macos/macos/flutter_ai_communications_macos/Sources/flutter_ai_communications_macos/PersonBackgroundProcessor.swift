import CoreImage
import CoreVideo
import Foundation
import Vision

/// Background blur and still replace on the Production video path.
final class PersonBackgroundProcessor {
  enum Kind {
    case none
    case blur(Int)
    case replace
  }

  private let context = CIContext(options: [.cacheIntermediates: false])
  private let segmentationRequest: VNGeneratePersonSegmentationRequest = {
    let request = VNGeneratePersonSegmentationRequest()
    request.qualityLevel = .balanced
    request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    return request
  }()
  private var kind: Kind = .none
  private var still: CIImage?

  func apply(_ args: [String: Any]) -> String {
    let kindName = args["kind"] as? String ?? "none"
    switch kindName {
    case "none":
      kind = .none
      still = nil
      return "ready"
    case "blur":
      let intensity = intArg(args, "intensity", 50)
      guard (0...100).contains(intensity) else {
        return "invalid"
      }
      kind = .blur(intensity)
      return "ready"
    case "replace":
      if let bytes = args["bytes"] as? Data, let image = CIImage(data: bytes) {
        still = image
        kind = .replace
        return "ready"
      }
      if let asset = args["asset"] as? String, !asset.isEmpty,
         let image = CIImage(contentsOf: URL(fileURLWithPath: asset))
      {
        still = image
        kind = .replace
        return "ready"
      }
      return "invalid"
    default:
      return "unavailable"
    }
  }

  private func intArg(_ args: [String: Any], _ key: String, _ fallback: Int) -> Int {
    if let number = args[key] as? NSNumber {
      return number.intValue
    }
    if let value = args[key] as? Int {
      return value
    }
    return fallback
  }

  func process(_ buffer: CVPixelBuffer) -> CVPixelBuffer {
    switch kind {
    case .none:
      return buffer
    case .blur(let intensity):
      return composite(buffer, background: blurred(buffer, intensity: intensity)) ?? buffer
    case .replace:
      return composite(buffer, background: scaledStill(to: buffer)) ?? buffer
    }
  }

  private func blurred(_ buffer: CVPixelBuffer, intensity: Int) -> CIImage? {
    let image = CIImage(cvPixelBuffer: buffer)
    let radius = Double(intensity) / 100.0 * 20.0
    if radius <= 0.5 {
      return image
    }
    return image.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: image.extent)
  }

  private func scaledStill(to buffer: CVPixelBuffer) -> CIImage? {
    guard let still else {
      return nil
    }
    let width = CGFloat(CVPixelBufferGetWidth(buffer))
    let height = CGFloat(CVPixelBufferGetHeight(buffer))
    let target = CGRect(x: 0, y: 0, width: width, height: height)
    let scale = max(width / still.extent.width, height / still.extent.height)
    return still
      .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      .cropped(to: target)
  }

  private func composite(_ buffer: CVPixelBuffer, background: CIImage?) -> CVPixelBuffer? {
    guard let background, let mask = personMask(buffer) else {
      return nil
    }
    let person = CIImage(cvPixelBuffer: buffer)
    let scaledMask = mask.transformed(
      by: CGAffineTransform(
        scaleX: person.extent.width / max(mask.extent.width, 1),
        y: person.extent.height / max(mask.extent.height, 1)
      )
    )
    let output = person.applyingFilter(
      "CIBlendWithMask",
      parameters: [
        kCIInputBackgroundImageKey: background,
        kCIInputMaskImageKey: scaledMask,
      ]
    )
    var dst: CVPixelBuffer?
    CVPixelBufferCreate(
      kCFAllocatorDefault,
      CVPixelBufferGetWidth(buffer),
      CVPixelBufferGetHeight(buffer),
      kCVPixelFormatType_32BGRA,
      [
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
      ] as CFDictionary,
      &dst
    )
    guard let dst else {
      return nil
    }
    context.render(output, to: dst)
    return dst
  }

  private func personMask(_ buffer: CVPixelBuffer) -> CIImage? {
    let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
    do {
      try handler.perform([segmentationRequest])
      guard let pixel = segmentationRequest.results?.first?.pixelBuffer else {
        return nil
      }
      return CIImage(cvPixelBuffer: pixel)
    } catch {
      return nil
    }
  }
}
