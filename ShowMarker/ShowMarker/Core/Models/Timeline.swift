import Foundation

// ✅ ИСПРАВЛЕНО: добавлен Sendable
struct Timeline: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    var audio: TimelineAudio?

    /// FPS таймлайна (25 / 30 / 50 / 60 / 100)
    var fps: Int

    /// Маркеры таймлайна
    var markers: [TimelineMarker]

    /// BPM (beats per minute) для таймлайна
    var bpm: Double?

    /// Включена ли сетка битов на таймлайне
    var isBeatGridEnabled: Bool

    /// Включена ли привязка маркеров к сетке битов
    var isSnapToGridEnabled: Bool

    /// Включен ли метроном
    var isMetronomeEnabled: Bool

    /// Сдвиг сетки битов в секундах (offset для первого бита)
    var beatGridOffset: Double

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        audio: TimelineAudio? = nil,
        fps: Int = 30,
        markers: [TimelineMarker] = [],
        bpm: Double? = nil,
        isBeatGridEnabled: Bool = false,
        isSnapToGridEnabled: Bool = false,
        isMetronomeEnabled: Bool = false,
        beatGridOffset: Double = 0
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.audio = audio
        self.fps = fps
        self.markers = markers
        self.bpm = bpm
        self.isBeatGridEnabled = isBeatGridEnabled
        self.isSnapToGridEnabled = isSnapToGridEnabled
        self.isMetronomeEnabled = isMetronomeEnabled
        self.beatGridOffset = beatGridOffset
    }
}

// MARK: - Codable with Migration Support

extension Timeline {
    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, audio, fps, markers
        case bpm, isBeatGridEnabled, isSnapToGridEnabled
        case isMetronomeEnabled, beatGridOffset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        audio = try container.decodeIfPresent(TimelineAudio.self, forKey: .audio)
        fps = try container.decode(Int.self, forKey: .fps)
        markers = try container.decode([TimelineMarker].self, forKey: .markers)

        // New fields with defaults for backward compatibility
        bpm = try container.decodeIfPresent(Double.self, forKey: .bpm)
        isBeatGridEnabled = (try? container.decode(Bool.self, forKey: .isBeatGridEnabled)) ?? false
        isSnapToGridEnabled = (try? container.decode(Bool.self, forKey: .isSnapToGridEnabled)) ?? false
        isMetronomeEnabled = (try? container.decode(Bool.self, forKey: .isMetronomeEnabled)) ?? false
        beatGridOffset = (try? container.decode(Double.self, forKey: .beatGridOffset)) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(audio, forKey: .audio)
        try container.encode(fps, forKey: .fps)
        try container.encode(markers, forKey: .markers)
        try container.encodeIfPresent(bpm, forKey: .bpm)
        try container.encode(isBeatGridEnabled, forKey: .isBeatGridEnabled)
        try container.encode(isSnapToGridEnabled, forKey: .isSnapToGridEnabled)
        try container.encode(isMetronomeEnabled, forKey: .isMetronomeEnabled)
        try container.encode(beatGridOffset, forKey: .beatGridOffset)
    }
}
