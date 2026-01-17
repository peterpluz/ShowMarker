import Foundation
import AVFoundation

struct WaveformGenerator {

    /// Генерация stereo waveform (min/max пары) как в Reaper
    /// Возвращает массив пар [min, max, min, max, ...]
    static func generateFullResolutionPeaks(
        from url: URL,
        baseBucketSize: Int = 32  // Детализация: меньше = больше деталей
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

        var values: [Float] = []  // Чередование [min, max, min, max, ...]
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
                    // Сохраняем min и max для stereo-отображения
                    values.append(minPeak)
                    values.append(maxPeak)
                    
                    maxPeak = 0
                    minPeak = 0
                    count = 0
                }
            }

            CMSampleBufferInvalidate(sb)
        }

        if count > 0 {
            values.append(minPeak)
            values.append(maxPeak)
        }

        return normalize(values)
    }

    /// Создание mipmap pyramid для разных уровней зума
    static func buildMipmaps(from base: [Float]) -> [[Float]] {
        var levels: [[Float]] = [base]
        var current = base

        // Создаём уровни с сохранением min/max пар
        while current.count > 100 {
            var next: [Float] = []
            next.reserveCapacity(current.count / 2)

            var i = 0
            while i < current.count {
                // Берём 2 пары (4 значения): min1, max1, min2, max2
                let end = min(i + 4, current.count)
                let slice = current[i..<end]
                
                if slice.count >= 2 {
                    // Находим общий min и max из всех значений
                    let minVal = slice.enumerated()
                        .filter { $0.offset % 2 == 0 }  // Только min значения
                        .map { $0.element }
                        .min() ?? 0
                    
                    let maxVal = slice.enumerated()
                        .filter { $0.offset % 2 == 1 }  // Только max значения
                        .map { $0.element }
                        .max() ?? 0
                    
                    next.append(minVal)
                    next.append(maxVal)
                }
                
                i += 4
            }

            if next.count >= 2 {
                levels.append(normalize(next))
                current = next
            } else {
                break
            }
        }

        return levels
    }

    // MARK: - Private

    private static func normalize(_ values: [Float]) -> [Float] {
        guard !values.isEmpty else { return values }
        
        // Находим максимальное абсолютное значение
        let maxAbs = values.map { abs($0) }.max() ?? 1.0
        
        guard maxAbs > 0 else { return values }
        
        // Нормализуем, сохраняя знак
        return values.map { $0 / maxAbs }
    }
}
