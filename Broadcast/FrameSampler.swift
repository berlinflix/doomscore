import CoreMedia
import CoreVideo
import ImageIO
import ReplayKit

/// Turns ReplayKit frames into the tiny inputs the detector needs, without
/// ever retaining the frame itself.
enum FrameSampler {
    /// Portrait-up frames only; reels feeds are portrait.
    static func isPortraitUp(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let value = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
              let orientation = CGImagePropertyOrientation(rawValue: value.uint32Value) else { return true }
        return orientation == .up
    }

    /// Averages a 4×4 sparse lattice per cell of the luma plane → LumaGrid.
    static func lumaGrid(from pixelBuffer: CVPixelBuffer, width gw: Int, height gh: Int) -> LumaGrid? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let planar = format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        let bgra = format == kCVPixelFormatType_32BGRA
        guard planar || bgra else { return nil }

        let base: UnsafeMutableRawPointer?
        let width: Int, height: Int, bytesPerRow: Int
        if planar {
            base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
            width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        } else {
            base = CVPixelBufferGetBaseAddress(pixelBuffer)
            width = CVPixelBufferGetWidth(pixelBuffer)
            height = CVPixelBufferGetHeight(pixelBuffer)
            bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        }
        guard let base, width >= gw, height >= gh else { return nil }
        let src = base.assumingMemoryBound(to: UInt8.self)

        let offsets: [Double] = [0.125, 0.375, 0.625, 0.875]
        let cellW = Double(width) / Double(gw)
        let cellH = Double(height) / Double(gh)
        var xs = [Int](repeating: 0, count: gw * 4)
        var ys = [Int](repeating: 0, count: gh * 4)
        for gx in 0..<gw { for i in 0..<4 { xs[gx * 4 + i] = min(width - 1, Int((Double(gx) + offsets[i]) * cellW)) } }
        for gy in 0..<gh { for i in 0..<4 { ys[gy * 4 + i] = min(height - 1, Int((Double(gy) + offsets[i]) * cellH)) } }

        var out = [UInt8](repeating: 0, count: gw * gh)
        for gy in 0..<gh {
            for gx in 0..<gw {
                var sum = 0
                for iy in 0..<4 {
                    let row = src + ys[gy * 4 + iy] * bytesPerRow
                    for ix in 0..<4 {
                        let x = xs[gx * 4 + ix]
                        if planar {
                            sum += Int(row[x])
                        } else {
                            let p = row + x * 4
                            sum += (Int(p[0]) * 29 + Int(p[1]) * 150 + Int(p[2]) * 77) >> 8
                        }
                    }
                }
                out[gy * gw + gx] = UInt8(truncatingIfNeeded: sum >> 4)
            }
        }
        return LumaGrid(width: gw, height: gh, values: out)
    }

    /// Reusable single-channel buffer for OCR (half resolution by default).
    static func makeGrayBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_OneComponent8, attributes, &buffer)
        return buffer
    }

    /// Box-downscales the luma of `source` into the gray `destination`.
    static func downscaleLuma(from source: CVPixelBuffer, into destination: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(destination, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }
        let format = CVPixelBufferGetPixelFormatType(source)
        let planar = format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        guard planar || format == kCVPixelFormatType_32BGRA else { return false }

        let srcBase = planar ? CVPixelBufferGetBaseAddressOfPlane(source, 0) : CVPixelBufferGetBaseAddress(source)
        let sw = planar ? CVPixelBufferGetWidthOfPlane(source, 0) : CVPixelBufferGetWidth(source)
        let sh = planar ? CVPixelBufferGetHeightOfPlane(source, 0) : CVPixelBufferGetHeight(source)
        let sbpr = planar ? CVPixelBufferGetBytesPerRowOfPlane(source, 0) : CVPixelBufferGetBytesPerRow(source)
        guard let srcBase, let dstBase = CVPixelBufferGetBaseAddress(destination) else { return false }
        let dw = CVPixelBufferGetWidth(destination)
        let dh = CVPixelBufferGetHeight(destination)
        let dbpr = CVPixelBufferGetBytesPerRow(destination)
        guard dw > 0, dh > 0, sw >= dw, sh >= dh else { return false }

        let src = srcBase.assumingMemoryBound(to: UInt8.self)
        let dst = dstBase.assumingMemoryBound(to: UInt8.self)
        let fx = sw / dw
        let fy = sh / dh
        let samplesX = max(1, min(fx, 2))
        let samplesY = max(1, min(fy, 2))
        let divisor = samplesX * samplesY

        for y in 0..<dh {
            let sy = min(y * sh / dh, sh - samplesY)
            let outRow = dst + y * dbpr
            for x in 0..<dw {
                let sx = min(x * sw / dw, sw - samplesX)
                var sum = 0
                for oy in 0..<samplesY {
                    let row = src + (sy + oy) * sbpr
                    for ox in 0..<samplesX {
                        if planar {
                            sum += Int(row[sx + ox])
                        } else {
                            let p = row + (sx + ox) * 4
                            sum += (Int(p[0]) * 29 + Int(p[1]) * 150 + Int(p[2]) * 77) >> 8
                        }
                    }
                }
                outRow[x] = UInt8(truncatingIfNeeded: sum / divisor)
            }
        }
        return true
    }
}
