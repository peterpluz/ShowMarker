import SwiftUI
import Foundation
import UniformTypeIdentifiers
import AVFoundation

struct TimelineScreen: View {

    @Binding var document: ShowMarkerDocument
    let timelineID: UUID

    @State private var isPickerPresented = false
    @State private var waveform: [Float] = []

    private var timelineIndex: Int? {
        document.file.project.timelines.firstIndex { $0.id == timelineID }
    }

    private var timeline: Timeline? {
        guard let index = timelineIndex else { return nil }
        return document.file.project.timelines[index]
    }

    var body: some View {
        VStack(spacing: 16) {
            if let timeline {
                if let audio = timeline.audio {
                    WaveformView(samples: waveform)

                    Text(audio.originalFileName)
                        .font(.callout)

                    Text("Длительность: \(format(audio.duration))")
                        .foregroundColor(.secondary)
                } else {
                    emptyState
                }
            }
        }
        .padding()
        .navigationTitle(timeline?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)

        .safeAreaInset(edge: .bottom) {
            Button(timeline?.audio == nil ? "Добавить аудиофайл" : "Заменить аудиофайл") {
                isPickerPresented = true
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }

        .fileImporter(
            isPresented: $isPickerPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false,
            onCompletion: handleAudio
        )

        .task {
            await loadWaveformIfNeeded()
        }

        // ✅ АКТУАЛЬНЫЙ onChange (iOS 17+)
        .onChange(of: timeline?.audio?.relativePath) {
            Task {
                await loadWaveformIfNeeded(force: true)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Нет аудиофайла")
                .foregroundColor(.secondary)
            Text("Добавьте аудио для работы с таймлайном")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Audio import

    private func handleAudio(_ result: Result<[URL], Error>) {
        guard
            case .success(let urls) = result,
            let url = urls.first
        else { return }

        Task {
            let asset = AVURLAsset(url: url)
            let duration = try? await asset.load(.duration)

            do {
                try document.addAudio(
                    to: timelineID,
                    sourceURL: url,
                    duration: duration?.seconds ?? 0
                )
            } catch {
                print("Audio copy failed:", error)
            }
        }
    }

    // MARK: - Waveform

    @MainActor
    private func loadWaveformIfNeeded(force: Bool = false) async {
        guard
            let audio = timeline?.audio,
            waveform.isEmpty || force
        else { return }

        let url = AudioStorage.url(for: audio.relativePath)

        do {
            let samples = try await WaveformLoader.loadSamples(from: url)
            waveform = samples
        } catch {
            waveform = []
        }
    }

    // MARK: - Helpers

    private func format(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
