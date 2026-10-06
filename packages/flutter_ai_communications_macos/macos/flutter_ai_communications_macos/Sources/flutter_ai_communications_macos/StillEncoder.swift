import CoreImage
import CoreVideo
import FlutterMacOS
import Foundation

enum StillEncoder {
  static func jpeg(from buffer: CVPixelBuffer) -> [String: Any]? {
    let image = CIImage(cvPixelBuffer: buffer)
    let context = CIContext(options: [.workingColorSpace: NSNull()])
    let colorSpace =
      CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard
      let data = context.jpegRepresentation(
        of: image,
        colorSpace: colorSpace,
        options: [
          kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption:
            0.9,
        ]
      )
    else {
      return nil
    }
    return [
      "bytes": FlutterStandardTypedData(bytes: data),
      "width": CVPixelBufferGetWidth(buffer),
      "height": CVPixelBufferGetHeight(buffer),
      "mime": "image/jpeg",
    ]
  }
}
