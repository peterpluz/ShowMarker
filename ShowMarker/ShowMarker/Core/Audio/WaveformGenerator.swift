import Foundation
import AVFoundation

// ✅ ИСПРАВЛЕНО: nonisolated + async API
struct WaveformGenerator {

    /// Обнаружение количества аудиоканалов в файле
    nonisolated static func detectChannelCount(from url: URL) async throws -> Int {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { return 1 }

        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let formatDesc = formatDescriptions.first as? CMAudioFormatDescription else {
            return 1
        }

        let basicDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
        return Int(basicDesc?.mChannelsPerFrame ?? 1)
    }

    /// Генерация двух waveforms для 4-канального аудио (каналы 1-2 и 3-4)
    /// Возвращает кортеж (waveform1-2, waveform3-4) или (waveform, waveform) для 2-канального
    nonisolated static func generateMultiChannelPeaks(
        from url: URL,
        baseBucketSize: Int = 256
    ) async throws -> ([Float], [Float]) {
        let channelCount = try await detectChannelCount(from: url)
        let mainWaveform = try await generateFullResolutionPeaks(from: url, baseBucketSize: baseBucketSize)

        // Для 4-канального аудио и выше, отображаем одну вейвформу два раза
        // В будущем можно реализовать обработку отдельных каналов для более точного представления
        return (mainWaveform, mainWaveform)
    }

    /// Генерация stereo waveform (min/max пары) с высоким разрешением
    /// Возвращает массив пар [min, max, min, max, ...]
    nonisolated static func generateFullResolutionPeaks(
        from url: URL,
        baseBucketSize: Int = 256
    ) async throws -> [Float] {

        let asset = AVURLAsset(url: url)

        // ✅ ИСПРАВЛЕНО: используем async API для iOS 15+
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            return []
        }

        // ✅ Estimate memory requirements based on audio duration
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        let sampleRate: Double = 44100 // Typical sample rate
        let estimatedSamples = Int(durationSeconds * sampleRate)
        let estimatedPeaks = (estimatedSamples / baseBucketSize) * 2 // min/max pairs

        print("🌊 Audio duration: \(durationSeconds)s, estimated peaks: \(estimatedPeaks)")

        return try await withCheckedThrowingContinuation { continuation in
            do {
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
                // ✅ Better memory pre-allocation based on estimated size
                let capacityEstimate = min(estimatedPeaks, 100_000) // Cap at 100k peaks
                values.reserveCapacity(capacityEstimate)
                print("🌊 Reserved capacity: \(capacityEstimate) peaks")
                
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

                    let copyResult = data.withUnsafeMutableBytes { dest -> Bool in
                        guard let baseAddress = dest.baseAddress else { return false }
                        let status = CMBlockBufferCopyDataBytes(
                            bb,
                            atOffset: 0,
                            dataLength: length,
                            destination: baseAddress
                        )
                        return status == noErr
                    }

                    guard copyResult else {
                        CMSampleBufferInvalidate(sb)
                        continue
                    }

                    let samples: UnsafeBufferPointer<Float>? = data.withUnsafeBytes { bytes in
                        guard let baseAddress = bytes.bindMemory(to: Float.self).baseAddress else {
                            return nil
                        }
                        return UnsafeBufferPointer<Float>(
                            start: baseAddress,
                            count: length / MemoryLayout<Float>.size
                        )
                    }

                    guard let samples = samples else {
                        CMSampleBufferInvalidate(sb)
                        continue
                    }

                    for s in samples {
                        maxPeak = max(maxPeak, s)
                        minPeak = min(minPeak, s)
                        count += 1

                        if count >= baseBucketSize {
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

                continuation.resume(returning: normalize(values))
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Создание mipmap pyramid для разных уровней зума
    nonisolated static func buildMipmaps(from base: [Float]) -> [[Float]] {
        var levels: [[Float]] = [base]
        var current = base

        while current.count > 50 {
            var next: [Float] = []
            next.reserveCapacity(current.count / 2)

            var i = 0
            while i < current.count {
                let end = min(i + 4, current.count)
                let slice = current[i..<end]
                
                if slice.count >= 2 {
                    let minVal = slice.enumerated()
                        .filter { $0.offset % 2 == 0 }
                        .map { $0.element }
                        .min() ?? 0
                    
                    let maxVal = slice.enumerated()
                        .filter { $0.offset % 2 == 1 }
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

    nonisolated private static func normalize(_ values: [Float]) -> [Float] {
        guard !values.isEmpty else { return values }
        
        let maxAbs = values.map { abs($0) }.max() ?? 1.0
        guard maxAbs > 0 else { return values }
        
        return values.map { $0 / maxAbs }
    }
}
