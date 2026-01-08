import Foundation
import AVFoundation

enum WaveformLoader {

    static func loadSamples(
        from url: URL,
        samplesCount: Int = 500
    ) async throws -> [Float] {

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { return [] }

        let reader = try AVAssetReader(asset: asset)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false
        ]

        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: settings
        )

        reader.add(output)
        reader.startReading()

        var rawSamples: [Float] = []

        while let buffer = output.copyNextSampleBuffer(),
              let block = CMSampleBufferGetDataBuffer(buffer) {

            let length = CMBlockBufferGetDataLength(block)
            var data = Data(count: length)

            _ = data.withUnsafeMutableBytes { ptr in
                CMBlockBufferCopyDataBytes(
                    block,
                    atOffset: 0,
                    dataLength: length,
                    destination: ptr.baseAddress!
                )
            }

            let floats = data.withUnsafeBytes { ptr -> [Float] in
                let count = length / MemoryLayout<Float>.size
                return Array(ptr.bindMemory(to: Float.self).prefix(count))
            }

            rawSamples.append(contentsOf: floats)
        }

        guard !rawSamples.isEmpty else { return [] }

        let step = max(rawSamples.count / samplesCount, 1)

        return stride(from: 0, to: rawSamples.count, by: step).map {
            abs(rawSamples[$0])
        }
    }
}
