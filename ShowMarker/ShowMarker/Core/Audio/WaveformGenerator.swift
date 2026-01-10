import Foundation
import AVFoundation

enum WaveformGenerator {

    /// Генерирует full-resolution пики (peak) из аудиофайла.
    /// baseBucketSize — сколько PCM-сэмплов в одном пике (512–2048 обычно).
    static func generateFullResolutionPeaks(
        from url: URL,
        baseBucketSize: Int = 1024
    ) throws -> [Float] {

        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else {
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

        var peaks: [Float] = []
        var bucket: [Float] = []
        bucket.reserveCapacity(baseBucketSize)

        while reader.status == .reading {
            guard let sb = output.copyNextSampleBuffer(),
                  let bb = CMSampleBufferGetDataBuffer(sb)
            else { break }

            let length = CMBlockBufferGetDataLength(bb)
            var data = Data(count: length)

            data.withUnsafeMutableBytes { dest in
                CMBlockBufferCopyDataBytes(
                    bb,
                    atOffset: 0,
                    dataLength: length,
                    destination: dest.baseAddress!
                )
            }

            let samples = data.withUnsafeBytes {
                Array(
                    UnsafeBufferPointer<Float>(
                        start: $0.bindMemory(to: Float.self).baseAddress!,
                        count: length / MemoryLayout<Float>.size
                    )
                )
            }

            for s in samples {
                bucket.append(abs(s))
                if bucket.count >= baseBucketSize {
                    peaks.append(bucket.max() ?? 0)
                    bucket.removeAll(keepingCapacity: true)
                }
            }

            CMSampleBufferInvalidate(sb)
        }

        if !bucket.isEmpty {
            peaks.append(bucket.max() ?? 0)
        }

        return normalize(peaks)
    }

    /// Строит mipmap уровни (каждый следующий — в 2 раза меньше)
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
                next.append(slice.max() ?? 0)
                i += 2
            }

            levels.append(normalize(next))
            current = next
        }

        return levels
    }

    private static func normalize(_ values: [Float]) -> [Float] {
        guard let maxVal = values.max(), maxVal > 0 else { return values }
        return values.map { min(1, $0 / maxVal) }
    }
}
