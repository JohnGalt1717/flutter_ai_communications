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

  private let context = CIContext(options: [
    .cacheIntermediates: false,
    .workingColorSpace: NSNull(),
  ])
  private let segmentationRequest: VNGeneratePersonSegmentationRequest = {
    let request = VNGeneratePersonSegmentationRequest()
    request.qualityLevel = .balanced
    request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    return request
  }()
  private let humanRequest = VNDetectHumanRectanglesRequest()
  private var kind: Kind = .none
  private var still: CIImage?
  private var lastMask: CIImage?
  private var ring: [CVPixelBuffer] = []
  private var ringIndex = 0
  private var lastOutput: CVPixelBuffer?

  func apply(_ args: [String: Any]) -> String {
    let kindName = args["kind"] as? String ?? "none"
    switch kindName {
    case "none":
      kind = .none
      still = nil
      lastMask = nil
      lastOutput = nil
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
      guard let background = blurred(buffer, intensity: intensity) else {
        return lastOutput ?? buffer
      }
      if let mask = personMask(buffer) {
        let out = composite(buffer, background: background, mask: mask)
        lastOutput = out ?? lastOutput
        return out ?? lastOutput ?? buffer
      }
      return lastOutput ?? buffer
    case .replace:
      guard let background = scaledStill(to: buffer) else {
        return lastOutput ?? buffer
      }
      if let mask = personMask(buffer) {
        let out = composite(buffer, background: background, mask: mask)
        lastOutput = out ?? lastOutput
        return out ?? lastOutput ?? buffer
      }
      return lastOutput ?? buffer
    }
  }

  private func blurred(_ buffer: CVPixelBuffer, intensity: Int) -> CIImage? {
    let image = CIImage(cvPixelBuffer: buffer)
    let radius = Double(intensity) / 100.0 * 18.0
    if radius <= 0.5 {
      return image
    }
    let extent = image.extent
    let scale: CGFloat = 0.4
    let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let blurred = small
      .clampedToExtent()
      .applyingGaussianBlur(sigma: radius)
      .cropped(to: small.extent)
    return blurred
      .transformed(by: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
      .cropped(to: extent)
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

  private func composite(
    _ buffer: CVPixelBuffer,
    background: CIImage,
    mask: CIImage
  ) -> CVPixelBuffer? {
    let person = CIImage(cvPixelBuffer: buffer)
    let scaledMask = preparedMask(mask, to: person.extent)
    let output = person.applyingFilter(
      "CIBlendWithMask",
      parameters: [
        kCIInputBackgroundImageKey: background,
        kCIInputMaskImageKey: scaledMask,
      ]
    )
    return render(output, like: buffer)
  }

  private func render(_ image: CIImage, like buffer: CVPixelBuffer) -> CVPixelBuffer? {
    guard let dst = nextDst(like: buffer) else {
      return nil
    }
    context.render(image, to: dst)
    return dst
  }

  private func nextDst(like buffer: CVPixelBuffer) -> CVPixelBuffer? {
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    if ring.count == 2 {
      let first = ring[0]
      if CVPixelBufferGetWidth(first) != width || CVPixelBufferGetHeight(first) != height {
        ring.removeAll()
      }
    }
    while ring.count < 2 {
      var dst: CVPixelBuffer?
      CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        [
          kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
          kCVPixelBufferMetalCompatibilityKey: true,
        ] as CFDictionary,
        &dst
      )
      guard let dst else {
        return nil
      }
      ring.append(dst)
    }
    let dst = ring[ringIndex % ring.count]
    ringIndex += 1
    return dst
  }

  private func preparedMask(_ mask: CIImage, to extent: CGRect) -> CIImage {
    let confident = mask.applyingFilter(
      "CIGammaAdjust",
      parameters: ["inputPower": 2.4]
    )
    let cleaned = confident
      .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: 2.5])
      .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 3.5])
    let scaled = cleaned.transformed(
      by: CGAffineTransform(
        scaleX: extent.width / max(cleaned.extent.width, 1),
        y: extent.height / max(cleaned.extent.height, 1)
      )
    )
    return scaled
      .clampedToExtent()
      .applyingGaussianBlur(sigma: 3)
      .cropped(to: extent)
  }

  private func personMask(_ buffer: CVPixelBuffer) -> CIImage? {
    let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
    do {
      try handler.perform([segmentationRequest, humanRequest])
      guard let pixel = segmentationRequest.results?.first?.pixelBuffer else {
        return lastMask
      }
      var mask = CIImage(cvPixelBuffer: pixel)
      let width = CGFloat(CVPixelBufferGetWidth(buffer))
      let height = CGFloat(CVPixelBufferGetHeight(buffer))
      if let gated = clipToHumans(mask, imageWidth: width, imageHeight: height) {
        mask = gated
      }
      lastMask = mask
      return mask
    } catch {
      return lastMask
    }
  }

  private func clipToHumans(
    _ mask: CIImage,
    imageWidth: CGFloat,
    imageHeight: CGFloat
  ) -> CIImage? {
    let humans = humanRequest.results ?? []
    guard !humans.isEmpty else {
      return mask
    }
    let maskW = mask.extent.width
    let maskH = mask.extent.height
    var union = CGRect.null
    for human in humans {
      var box = VNImageRectForNormalizedRect(
        human.boundingBox,
        Int(maskW.rounded()),
        Int(maskH.rounded())
      )
      box = box.insetBy(dx: -box.width * 0.06, dy: -box.height * 0.1)
      union = union.union(box)
    }
    union = union.intersection(mask.extent)
    guard !union.isNull, union.width > 2, union.height > 2 else {
      return mask
    }
    let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
      .cropped(to: union)
    let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
      .cropped(to: mask.extent)
    let gate = white.composited(over: black)
    return mask.applyingFilter(
      "CIMultiplyCompositing",
      parameters: [kCIInputBackgroundImageKey: gate]
    )
  }
}
