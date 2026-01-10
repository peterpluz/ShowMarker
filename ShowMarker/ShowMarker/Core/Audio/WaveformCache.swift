import Foundation

enum WaveformCache {

    /// Загружает waveform из кэша или генерирует и сохраняет.
    /// - Parameters:
    ///   - audioURL: URL аудиофайла
    ///   - samplesCount: количество точек waveform
    /// - Returns: массив амплитуд 0…1
    static func loadOrGenerate(
        audioURL: URL,
        samplesCount: Int
    ) throws -> [Float] {

        let cacheURL = cacheFileURL(
            for: audioURL,
            samplesCount: samplesCount
        )

        if let cached = load(from: cacheURL) {
            return cached
        }

        let waveform = try WaveformGenerator.generate(
            from: audioURL,
            samplesCount: samplesCount
        )

        save(waveform, to: cacheURL)
        return waveform
    }

    // MARK: - Cache file

    private static func cacheFileURL(
        for audioURL: URL,
        samplesCount: Int
    ) -> URL {

        let base = audioURL.deletingPathExtension().lastPathComponent
        let fileName = "\(base).waveform.\(samplesCount).bin"

        return FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
    }

    // MARK: - IO

    private static func save(
        _ waveform: [Float],
        to url: URL
    ) {
        let data = waveform.withUnsafeBufferPointer {
            Data(buffer: $0)
        }

        try? data.write(to: url, options: .atomic)
    }

    private static func load(
        from url: URL
    ) -> [Float]? {

        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes {
            Array(
                UnsafeBufferPointer<Float>(
                    start: $0.bindMemory(to: Float.self).baseAddress!,
                    count: count
                )
            )
        }
    }
}
