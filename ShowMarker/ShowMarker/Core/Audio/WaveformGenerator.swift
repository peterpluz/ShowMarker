import Foundation
import AVFoundation

struct WaveformGenerator {

    /// Генерация полной детализации waveform для разных уровней зума
    /// Создаёт максимально детализированный базовый уровень (1 sample per bucket)
    static func generateFullResolutionPeaks(
        from url: URL,
        baseBucketSize: Int = 64  // Уменьшено для большей детализации
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
        var sumSquares: Float = 0
        var maxPeak: Float = 0
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
                let absValue = abs(s)
                sumSquares += s * s
                maxPeak = max(maxPeak, absValue)
                count += 1

                if count >= baseBucketSize {
                    // Используем комбинацию RMS и Peak для лучшей визуализации
                    let rms = sqrt(sumSquares / Float(count))
                    let combined = (rms * 0.7 + maxPeak * 0.3)  // Weighted average
                    values.append(combined)
                    
                    sumSquares = 0
                    maxPeak = 0
                    count = 0
                }
            }

            CMSampleBufferInvalidate(sb)
        }

        if count > 0 {
            let rms = sqrt(sumSquares / Float(count))
            let combined = (rms * 0.7 + maxPeak * 0.3)
            values.append(combined)
        }

        return normalize(values)
    }

    /// Создание множества уровней детализации (mipmap pyramid)
    /// Каждый следующий уровень имеет в 2 раза меньше сэмплов
    static func buildMipmaps(from base: [Float]) -> [[Float]] {
        var levels: [[Float]] = [base]
        var current = base

        // Создаём уровни до очень малого количества сэмплов
        while current.count > 100 {
            var next: [Float] = []
            next.reserveCapacity(current.count / 2)

            var i = 0
            while i < current.count {
                let end = min(i + 2, current.count)
                let slice = current[i..<end]
                
                // Используем максимальное значение для сохранения пиков
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
        return values.map { min(1, $0 / maxVal) }
    }
}
