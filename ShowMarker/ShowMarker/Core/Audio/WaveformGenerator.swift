import Foundation
import AVFoundation

struct WaveformGenerator {

    static func generateFullResolutionPeaks(
        from url: URL,
        baseBucketSize: Int = 1024
    ) throws -> [Float] {

        let asset = AVURLAsset(url: url)
        
        // Подавляем warning для deprecated API (используем старый API для синхронности)
        let tracks = asset.tracks(withMediaType: .audio)
        guard let track = tracks.first else {
            return []
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: outputSettings
        )
        reader.add(output)
        reader.startReading()

        var values: [Float] = []
        var sumSquares: Float = 0
        var count: Int = 0

        while reader.status == .reading {
            guard
                let sb = output.copyNextSampleBuffer(),
                let bb = CMSampleBufferGetDataBuffer(sb)
            else { break }

            let length = CMBlockBufferGetDataLength(bb)
            var data = Data(count: length)

            _ = data.withUnsafeMutableBytes { dest in
                CMBlockBufferCopyDataBytes(
                    bb,
                    atOffset: 0,
                    dataLength: length,
                    destination: dest.baseAddress!
                )
            }

            let samples = data.withUnsafeBytes {
                UnsafeBufferPointer<Float>(
                    start: $0.bindMemory(to: Float.self).baseAddress!,
                    count: length / MemoryLayout<Float>.size
                )
            }

            for s in samples {
                sumSquares += s * s
                count += 1

                if count >= baseBucketSize {
                    let rms = sqrt(sumSquares / Float(count))
                    values.append(rms)
                    sumSquares = 0
                    count = 0
                }
            }

            CMSampleBufferInvalidate(sb)
        }

        if count > 0 {
            let rms = sqrt(sumSquares / Float(count))
            values.append(rms)
        }

        return normalize(values)
    }

    static func buildMipmaps(from base: [Float]) -> [[Float]] {
        var levels: [[Float]] = [base]
        var current = base

        while current.count > 300 {
            var next: [Float] = []
            next.reserveCapacity(current.count / 2)

            var i = 0
            while i < current.count {
                let end = min(i + 2, current.count)
                let slice = current[i..<end]
                let rms = sqrt(slice.map { $0 * $0 }.reduce(0, +) / Float(slice.count))
                next.append(rms)
                i += 2
            }

            levels.append(normalize(next))
            current = next
        }

        return levels
    }

    // MARK: - Private

    private static func normalize(_ values: [Float]) -> [Float] {
        guard let maxVal = values.max(), maxVal > 0 else { return values }
        return values.map { min(1, $0 / maxVal) }
    }
}
