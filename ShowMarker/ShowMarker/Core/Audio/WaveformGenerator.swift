import Foundation
import AVFoundation

enum WaveformGenerator {

    /// Генерирует waveform из аудиофайла.
    /// - Parameters:
    ///   - url: URL аудиофайла
    ///   - samplesCount: сколько точек waveform нужно (например 100–300)
    /// - Returns: массив амплитуд 0…1
    static func generate(
        from url: URL,
        samplesCount: Int
    ) throws -> [Float] {

        let asset = AVURLAsset(url: url)
        let track = asset.tracks(withMediaType: .audio).first
        guard let track else { return [] }

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

        var allSamples: [Float] = []

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer(),
                  let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)
            else {
                break
            }

            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)

            data.withUnsafeMutableBytes { dest in
                CMBlockBufferCopyDataBytes(
                    blockBuffer,
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

            allSamples.append(contentsOf: samples)
            CMSampleBufferInvalidate(sampleBuffer)
        }

        if allSamples.isEmpty {
            return []
        }

        return downsample(samples: allSamples, to: samplesCount)
    }

    // MARK: - Downsampling

    private static func downsample(
        samples: [Float],
        to count: Int
    ) -> [Float] {

        guard count > 0 else { return [] }

        let samplesPerBucket = max(1, samples.count / count)
        var result: [Float] = []
        result.reserveCapacity(count)

        var index = 0
        while index < samples.count {
            let end = min(index + samplesPerBucket, samples.count)
            let slice = samples[index..<end]

            let peak = slice.map { abs($0) }.max() ?? 0
            result.append(min(1, peak))

            index += samplesPerBucket
        }

        // нормализуем до ровного count
        if result.count > count {
            return Array(result.prefix(count))
        } else if result.count < count {
            return result + Array(repeating: 0, count: count - result.count)
        }

        return result
    }
}
