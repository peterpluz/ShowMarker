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

    /// Выбор оптимального уровня детализации на основе зума и ширины экрана
    static func bestLevel(
        from cached: CachedWaveform,
        targetSamples: Int,
        zoomScale: CGFloat
    ) -> [Float] {
        
        // При большом зуме используем более детальные уровни
        let adjustedTarget = Int(Double(targetSamples) * Double(zoomScale))
        
        // Находим ближайший уровень, который больше или равен target
        // Это даёт нам максимальную детализацию без потери производительности
        let level = cached.mipmaps.min { a, b in
            let diffA = abs(a.count - adjustedTarget)
            let diffB = abs(b.count - adjustedTarget)
            
            // Предпочитаем уровень с большим количеством сэмплов при равной разнице
            if diffA == diffB {
                return a.count > b.count
            }
            return diffA < diffB
        }
        
        return level ?? cached.mipmaps.last ?? []
    }

    // MARK: - Private

    private static func cacheURL(for key: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(key).waveform.json")
    }
}
