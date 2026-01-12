import Foundation

struct WaveformCache {

    struct CachedWaveform: Codable {
        let mipmaps: [[Float]]
    }

    static func generateAndCache(
        audioURL: URL,
        cacheKey: String
    ) throws -> CachedWaveform {

        let base = try WaveformGenerator.generateFullResolutionPeaks(from: audioURL)
        let mipmaps = WaveformGenerator.buildMipmaps(from: base)
        let cached = CachedWaveform(mipmaps: mipmaps)

        let url = cacheURL(for: cacheKey)
        let data = try JSONEncoder().encode(cached)
        try data.write(to: url, options: .atomic)

        return cached
    }

    static func load(cacheKey: String) -> CachedWaveform? {
        let url = cacheURL(for: cacheKey)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CachedWaveform.self, from: data)
    }

    static func bestLevel(
        from cached: CachedWaveform,
        targetSamples: Int
    ) -> [Float] {
        return cached.mipmaps.min {
            abs($0.count - targetSamples) < abs($1.count - targetSamples)
        } ?? []
    }

    // MARK: - Private

    private static func cacheURL(for key: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(key).waveform.json")
    }
}
