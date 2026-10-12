import Foundation
import UIKit
import ImageIO

/// Called off the main actor. Downsample before decoding full-size pixels.
enum ImageProcessing {
    static func thumbnail(_ bytes: Data, maxSize: Int) -> UIImage? {
        guard !Task.isCancelled,
              let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0,
              width.doubleValue * height.doubleValue <= 80_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary), !Task.isCancelled else { return nil }
        return UIImage(cgImage: image)
    }

    static func importJPEG(_ bytes: Data) throws -> Data {
        try Task.checkCancellation()
        guard bytes.count <= 20_000_000,
              let image = thumbnail(bytes, maxSize: 1200),
              let jpeg = image.jpegData(compressionQuality: 0.8), jpeg.count <= 2_000_000 else {
            throw InputError.invalid("Foto non leggibile o troppo grande: scegli un’altra immagine.")
        }
        try Task.checkCancellation()
        return jpeg
    }
}
