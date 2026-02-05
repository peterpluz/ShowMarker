@preconcurrency import Foundation
import AVFoundation

// MARK: - Cached Data Structure

struct CachedWaveformData: Codable {
    let mipmaps: [[Float]]
    let generatedAt: Date
    let audioID: String
}

// MARK: - Waveform Cache

struct WaveformCache {
    
    private static let cacheDirectory: URL = {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("WaveformCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    
    // MARK: - Generate and Cache
    
    static func generateAndCache(
        audioURL: URL,
        cacheKey: String
    ) async throws -> CachedWaveformData {

        // ✅ Adaptive bucket size based on file duration
        let asset = AVURLAsset(url: audioURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        // Use larger buckets for longer files to reduce memory usage
        let bucketSize: Int
        switch durationSeconds {
        case 0..<60:        // < 1 minute
            bucketSize = 256
        case 60..<300:      // 1-5 minutes
            bucketSize = 512
        case 300..<900:     // 5-15 minutes
            bucketSize = 1024
        default:            // > 15 minutes
            bucketSize = 2048
        }

        print("🌊 Using adaptive bucket size: \(bucketSize) for \(durationSeconds)s audio")

        // ✅ ИСПРАВЛЕНО: вызываем async функции напрямую
        let peaks = try await WaveformGenerator.generateFullResolutionPeaks(
            from: audioURL,
            baseBucketSize: bucketSize
        )
        
        print("✅ Raw peaks generated: \(peaks.count) samples")
        
        // ✅ buildMipmaps теперь nonisolated и синхронный
        let mipmaps = WaveformGenerator.buildMipmaps(from: peaks)
        print("✅ Mipmaps built: \(mipmaps.count) levels")
        
        let cached = CachedWaveformData(
            mipmaps: mipmaps,
            generatedAt: Date(),
            audioID: cacheKey
        )
        
        // Сохраняем в фоне
        Task.detached(priority: .background) {
            try? save(cached, cacheKey: cacheKey)
        }
        
        return cached
    }
    
    // MARK: - Load
    
    static func load(cacheKey: String) -> CachedWaveformData? {
        let fileURL = cacheDirectory.appendingPathComponent("\(cacheKey).waveform")
        
        guard
            FileManager.default.fileExists(atPath: fileURL.path),
            let data = try? Data(contentsOf: fileURL)
        else {
            return nil
        }
        
        return try? JSONDecoder().decode(CachedWaveformData.self, from: data)
    }
    
    // MARK: - Save

    private static func save(_ cached: CachedWaveformData, cacheKey: String) throws {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let cacheDir = paths[0].appendingPathComponent("WaveformCache", isDirectory: true)

        let fileURL = cacheDir.appendingPathComponent("\(cacheKey).waveform")
        // Create mutable copy to avoid Sendable conformance issues
        let encodable = CachedWaveformData(mipmaps: cached.mipmaps, generatedAt: cached.generatedAt, audioID: cached.audioID)
        let data = try JSONEncoder().encode(encodable)
        try data.write(to: fileURL, options: .atomic)
        print("✅ Waveform saved to cache: \(fileURL.lastPathComponent)")
    }
    
    // MARK: - Clear
    
    static func clearAll() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        )
        
        for file in files {
            try FileManager.default.removeItem(at: file)
        }
    }
}
