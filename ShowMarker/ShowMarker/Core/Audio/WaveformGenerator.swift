import Foundation
import AVFoundation

struct WaveformGenerator {

    /// Генерация максимально детализированной waveform
    /// baseBucketSize = 16 означает ~16 аудио-сэмплов на 1 визуальный бар
    static func generateFullResolutionPeaks(
        from url: URL,
        baseBucketSize: Int = 16
    ) throws -> [Float] {

        let asset = AVURLAsset(url: url)
        
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
        var maxPeak: Float = 0
        var minPeak: Float = 0
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
                maxPeak = max(maxPeak, s)
                minPeak = min(minPeak, s)
                count += 1

                if count >= baseBucketSize {
                    // Используем максимальное абсолютное значение (peak)
                    let peak = max(abs(maxPeak), abs(minPeak))
                    values.append(peak)
                    
                    maxPeak = 0
                    minPeak = 0
                    count = 0
                }
            }

            CMSampleBufferInvalidate(sb)
        }

        if count > 0 {
            let peak = max(abs(maxPeak), abs(minPeak))
            values.append(peak)
        }

        return normalize(values)
    }

    /// Создание mipmap pyramid для разных уровней зума
    static func buildMipmaps(from base: [Float]) -> [[Float]] {
        var levels: [[Float]] = [base]
        var current = base

        // Создаём уровни пока не дойдём до минимума
        while current.count > 50 {
            var next: [Float] = []
            next.reserveCapacity(current.count / 2)

            var i = 0
            while i < current.count {
                let end = min(i + 2, current.count)
                let slice = current[i..<end]
                
                // Сохраняем максимальный пик
                let maxVal = slice.max() ?? 0
                next.append(maxVal)
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
        return values.map { $0 / maxVal }
    }
}
