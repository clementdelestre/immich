import CoreGraphics
import Flutter
import UIKit
import Vision

private let maxSide = 3072

class SubjectSegmentationApiImpl: SubjectSegmentationApi {
  private let queue = DispatchQueue(label: "app.immich.subjectSegmentation", qos: .userInitiated)

  func extractSubject(
    rgba: FlutterStandardTypedData,
    width: Int64,
    height: Int64,
    x: Double,
    y: Double,
    completion: @escaping (Result<SubjectCutout?, Error>) -> Void
  ) {
    queue.async {
      guard #available(iOS 17.0, *) else { return completion(.success(nil)) }
      completion(Result { try extract(rgba.data, width: Int(width), height: Int(height), x: x, y: y) })
    }
  }

  func copyImageToClipboard(path: String) throws {
    UIPasteboard.general.image = UIImage(contentsOfFile: path)
  }
}

@available(iOS 17.0, *)
private func extract(_ rgba: Data, width sourceWidth: Int, height sourceHeight: Int, x: Double, y: Double) throws
  -> SubjectCutout?
{
  let scale = min(1, Double(maxSide) / Double(max(sourceWidth, sourceHeight)))
  let width = Int(Double(sourceWidth) * scale)
  let height = Int(Double(sourceHeight) * scale)
  guard let full = makeImage(rgba, width: sourceWidth, height: sourceHeight),
    var pixels = render(full, width: width, height: height),
    let source = makeImage(pixels, width: width, height: height)
  else { return nil }

  let n = width * height
  let seed = Int(y * Double(height - 1)) * width + Int(x * Double(width - 1))
  guard var subject = try segment(source, x: x, y: y) else { return nil }
  cleanUpMask(&subject, width: width, height: height, seed: seed)

  // Vision masks are coarse, a second pass cropped to the subject gives sharper edges.
  guard let bounds = maskBounds(subject, width: width, height: height) else { return nil }
  let crop = bounds.insetBy(dx: -(bounds.width * 0.15 + 8), dy: -(bounds.height * 0.15 + 8)).integral
    .intersection(CGRect(x: 0, y: 0, width: width, height: height))
  if crop.width * crop.height < Double(n) * 0.6, let zoomed = source.cropping(to: crop) {
    let zx = (x * Double(width - 1) - crop.minX) / crop.width
    let zy = (y * Double(height - 1) - crop.minY) / crop.height
    if let refined = try segment(zoomed, x: zx, y: zy) {
      subject = [Bool](repeating: false, count: n)
      for py in 0..<zoomed.height {
        for px in 0..<zoomed.width where refined[py * zoomed.width + px] {
          subject[(Int(crop.minY) + py) * width + Int(crop.minX) + px] = true
        }
      }
      cleanUpMask(&subject, width: width, height: height, seed: seed)
    }
  }

  guard let subjectBounds = maskBounds(subject, width: width, height: height) else { return nil }
  // The anti-aliased edge spills one pixel outside the mask.
  let box = subjectBounds.insetBy(dx: -1, dy: -1).intersection(CGRect(x: 0, y: 0, width: width, height: height))
  for py in Int(box.minY)..<Int(box.maxY) {
    for px in Int(box.minX)..<Int(box.maxX) {
      let i = py * width + px
      let alpha = edgeAlpha(subject, width: width, height: height, x: px, y: py)
      for c in 0..<4 {
        pixels[i * 4 + c] = UInt8(Int(pixels[i * 4 + c]) * alpha / 255)
      }
    }
  }
  guard let sticker = makeImage(pixels, width: width, height: height)?.cropping(to: box),
    let png = UIImage(cgImage: sticker).pngData()
  else { return nil }

  return SubjectCutout(
    png: FlutterStandardTypedData(bytes: png),
    left: box.minX / Double(width),
    top: box.minY / Double(height),
    width: box.width / Double(width),
    height: box.height / Double(height)
  )
}

@available(iOS 17.0, *)
private func segment(_ image: CGImage, x: Double, y: Double) throws -> [Bool]? {
  let handler = VNImageRequestHandler(cgImage: image)
  let request = VNGenerateForegroundInstanceMaskRequest()
  try handler.perform([request])
  guard let observation = request.results?.first else { return nil }

  let instances = observation.instanceMask
  CVPixelBufferLockBaseAddress(instances, .readOnly)
  let instanceWidth = CVPixelBufferGetWidth(instances)
  let instanceHeight = CVPixelBufferGetHeight(instances)
  let instanceRow = CVPixelBufferGetBytesPerRow(instances)
  let labels = CVPixelBufferGetBaseAddress(instances)!.assumingMemoryBound(to: UInt8.self)
  let instance = labels[
    min(instanceHeight - 1, Int(y * Double(instanceHeight))) * instanceRow
      + min(instanceWidth - 1, Int(x * Double(instanceWidth)))]
  CVPixelBufferUnlockBaseAddress(instances, .readOnly)
  guard instance != 0 else { return nil }

  let mask = try observation.generateScaledMaskForImage(forInstances: [Int(instance)], from: handler)
  CVPixelBufferLockBaseAddress(mask, .readOnly)
  defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
  let maskWidth = CVPixelBufferGetWidth(mask)
  let maskHeight = CVPixelBufferGetHeight(mask)
  let maskRow = CVPixelBufferGetBytesPerRow(mask)
  let base = CVPixelBufferGetBaseAddress(mask)!

  var subject = [Bool](repeating: false, count: image.width * image.height)
  for py in 0..<image.height {
    let row = base.advanced(by: (py * maskHeight / image.height) * maskRow).assumingMemoryBound(to: Float32.self)
    for px in 0..<image.width {
      subject[py * image.width + px] = row[px * maskWidth / image.width] > 0.5
    }
  }
  return subject
}

private func makeImage(_ data: Data, width: Int, height: Int) -> CGImage? {
  guard let provider = CGDataProvider(data: data as CFData) else { return nil }
  return CGImage(
    width: width,
    height: height,
    bitsPerComponent: 8,
    bitsPerPixel: 32,
    bytesPerRow: width * 4,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
    provider: provider,
    decode: nil,
    shouldInterpolate: true,
    intent: .defaultIntent
  )
}

private func makeImage(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
  makeImage(Data(pixels), width: width, height: height)
}

private func render(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
  var pixels = [UInt8](repeating: 0, count: width * height * 4)
  let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
    guard
      let context = CGContext(
        data: buffer.baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return false }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return true
  }
  return drawn ? pixels : nil
}

// Keeps the region under the touch point and fills small holes left by low confidence patches.
private func cleanUpMask(_ subject: inout [Bool], width: Int, height: Int, seed: Int) {
  let n = width * height
  var queue = [Int](repeating: 0, count: n)
  if subject[seed] {
    var region = [Bool](repeating: false, count: n)
    _ = floodFill(width: width, height: height, seeds: [seed], visited: &region, queue: &queue) { subject[$0] }
    subject = region
  }

  var outside = [Bool](repeating: false, count: n)
  let border = Array(0..<width) + Array((n - width)..<n) + stride(from: 0, to: n, by: width).flatMap { [$0, $0 + width - 1] }
  _ = floodFill(width: width, height: height, seeds: border, visited: &outside, queue: &queue) { !subject[$0] }

  // Bigger holes are real gaps, e.g. between an arm and the body.
  let maxHole = subject.reduce(0) { $1 ? $0 + 1 : $0 } / 50
  var hole = [Bool](repeating: false, count: n)
  for i in 0..<n where !subject[i] && !outside[i] && !hole[i] {
    let size = floodFill(width: width, height: height, seeds: [i], visited: &hole, queue: &queue) { !subject[$0] }
    if size <= maxHole {
      for k in 0..<size { subject[queue[k]] = true }
    }
  }
}

// Filled pixels are left in queue[0..<result].
private func floodFill(
  width: Int,
  height: Int,
  seeds: [Int],
  visited: inout [Bool],
  queue: inout [Int],
  include: (Int) -> Bool
) -> Int {
  let n = width * height
  var head = 0
  var tail = 0
  for s in seeds where !visited[s] && include(s) {
    visited[s] = true
    queue[tail] = s
    tail += 1
  }
  while head < tail {
    let i = queue[head]
    head += 1
    let x = i % width
    for j in [x > 0 ? i - 1 : -1, x < width - 1 ? i + 1 : -1, i - width, i + width]
    where j >= 0 && j < n && !visited[j] && include(j) {
      visited[j] = true
      queue[tail] = j
      tail += 1
    }
  }
  return tail
}

private func edgeAlpha(_ subject: [Bool], width: Int, height: Int, x: Int, y: Int) -> Int {
  var count = 0
  for dy in -1...1 {
    let yy = min(max(y + dy, 0), height - 1)
    for dx in -1...1 where subject[yy * width + min(max(x + dx, 0), width - 1)] {
      count += 1
    }
  }
  return count * 255 / 9
}

private func maskBounds(_ subject: [Bool], width: Int, height: Int) -> CGRect? {
  var minX = width, minY = height, maxX = -1, maxY = -1
  for py in 0..<height {
    for px in 0..<width where subject[py * width + px] {
      minX = min(minX, px)
      maxX = max(maxX, px)
      minY = min(minY, py)
      maxY = max(maxY, py)
    }
  }
  return maxX < 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}
