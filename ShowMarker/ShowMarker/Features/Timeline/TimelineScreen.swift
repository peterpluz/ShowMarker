import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct TimelineScreen: View {

    @ObservedObject var document: ShowMarkerDocument
    let timelineID: UUID

    @State private var isPickerPresented = false

    private var timelineIndex: Int? {
        document.file.project.timelines.firstIndex { $0.id == timelineID }
    }

    private var timeline: Timeline? {
        guard let index = timelineIndex else { return nil }
        return document.file.project.timelines[index]
    }

    var body: some View {
        VStack {
            if let timeline {
                if timeline.audio == nil {
                    emptyState
                } else {
                    audioState(timeline)
                }
            } else {
                Text("Таймлайн не найден")
                    .foregroundColor(.secondary)
            }
        }
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
    }

    // MARK: - States

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

    private func audioState(_ timeline: Timeline) -> some View {
        VStack(spacing: 12) {
            Text(timeline.audio?.originalFileName ?? "")
            Text("Длительность: \(format(timeline.audio?.duration ?? 0))")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

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

    private func format(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
