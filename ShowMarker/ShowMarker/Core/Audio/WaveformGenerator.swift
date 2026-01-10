import Foundation
import AVFoundation

enum WaveformGenerator {

    static func generate(
        from url: URL,
        samplesCount: Int
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

        var samples: [Float] = []

        while reader.status == .reading {
            guard
                let buffer = output.copyNextSampleBuffer(),
                let block = CMSampleBufferGetDataBuffer(buffer)
            else { break }

            let length = CMBlockBufferGetDataLength(block)
            var data = Data(count: length)

            data.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(
                    block,
                    atOffset: 0,
                    dataLength: length,
                    destination: $0.baseAddress!
                )
            }

            let chunk = data.withUnsafeBytes {
                Array(
                    UnsafeBufferPointer<Float>(
                        start: $0.bindMemory(to: Float.self).baseAddress!,
                        count: length / MemoryLayout<Float>.size
                    )
                )
            }

            samples.append(contentsOf: chunk)
            CMSampleBufferInvalidate(buffer)
        }

        guard !samples.isEmpty else { return [] }

        return buildSeratoLikeWaveform(
            samples: samples,
            targetCount: samplesCount
        )
    }

    // MARK: - Serato-like waveform

    private static func buildSeratoLikeWaveform(
        samples: [Float],
        targetCount: Int
    ) -> [Float] {

        let bucketSize = max(1, samples.count / targetCount)
        var peaks: [Float] = []
        peaks.reserveCapacity(targetCount)

        var index = 0
        while index < samples.count {
            let end = min(index + bucketSize, samples.count)
            let slice = samples[index..<end]

            let peak = slice.map { abs($0) }.max() ?? 0

            // soft compression (читаемо, но не плоско)
            let compressed = pow(peak, 0.5)

            peaks.append(compressed)
            index += bucketSize
        }

        // median smoothing — убираем шум, сохраняем форму
        let filtered = medianSmooth(peaks, radius: 1)

        // глобальная нормализация
        let maxVal = filtered.max() ?? 1
        guard maxVal > 0 else { return filtered }

        return filtered.map { min(1, $0 / maxVal) }
    }

    // MARK: - Median smoothing (НЕ blur)

    private static func medianSmooth(
        _ values: [Float],
        radius: Int
    ) -> [Float] {

        guard radius > 0 else { return values }

        var result = values

        for i in values.indices {
            let start = max(0, i - radius)
            let end = min(values.count - 1, i + radius)
            let window = Array(values[start...end]).sorted()
            result[i] = window[window.count / 2]
        }

        return result
    }
}
