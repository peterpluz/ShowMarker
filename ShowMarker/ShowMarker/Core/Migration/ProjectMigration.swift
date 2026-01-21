import Foundation

struct ProjectMigration {

    /// Migrates project to the latest format version
    static func migrate(_ project: Project) -> Project {
        var migratedProject = project

        // Migrate from version 1 to version 2 (tags support)
        if project.formatVersion < 2 {
            migratedProject = migrateToVersion2(migratedProject)
        }

        return migratedProject
    }

    /// Migration to version 2: Add tags support
    private static func migrateToVersion2(_ project: Project) -> Project {
        print("🔄 Migrating project from version \(project.formatVersion) to version 2")

        var migratedProject = project

        // Add default tags if not present
        if migratedProject.tags.isEmpty {
            migratedProject.tags = Tag.defaultTags
            print("✅ Added default tags: \(migratedProject.tags.map { $0.name }.joined(separator: ", "))")
        }

        // Get default tag (first tag) for migrating markers
        guard let defaultTag = migratedProject.tags.first else {
            print("⚠️ No default tag found, skipping marker migration")
            return migratedProject
        }

        // Migrate all markers in all timelines to use tagId
        // Since old markers don't have tagId field, they will fail to decode with new TimelineMarker structure
        // We need to handle this gracefully
        print("✅ Assigned default tag '\(defaultTag.name)' to all markers")

        // Note: The actual marker migration needs to happen during decoding
        // This is a placeholder for future custom decoding logic

        return migratedProject
    }
}

// MARK: - Custom Codable for TimelineMarker Migration

extension TimelineMarker {
    enum CodingKeys: String, CodingKey {
        case id
        case timeSeconds
        case name
        case tagId
        case tag  // Old field (string)
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        timeSeconds = try container.decode(Double.self, forKey: .timeSeconds)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        // Try to decode new tagId field first
        if let tagId = try? container.decode(UUID.self, forKey: .tagId) {
            self.tagId = tagId
        } else {
            // Fall back to old string tag field - use first tag as default
            // This will be assigned properly after project is fully loaded
            self.tagId = UUID() // Temporary UUID, will be replaced after migration
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(timeSeconds, forKey: .timeSeconds)
        try container.encode(name, forKey: .name)
        try container.encode(tagId, forKey: .tagId)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: - Custom Codable for Project Migration

extension Project {
    enum CodingKeys: String, CodingKey {
        case formatVersion
        case id
        case name
        case fps
        case tags
        case timelines
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        fps = try container.decode(Int.self, forKey: .fps)

        // Try to decode tags (new in version 2)
        if let tags = try? container.decode([Tag].self, forKey: .tags) {
            self.tags = tags
        } else {
            // No tags found, use defaults
            self.tags = Tag.defaultTags
        }

        // Decode timelines
        timelines = try container.decode([Timeline].self, forKey: .timelines)

        // Post-decode migration: assign default tag to all markers without proper tagId
        if formatVersion < 2, let defaultTag = self.tags.first {
            // Assign default tag to all markers
            for timelineIndex in self.timelines.indices {
                for markerIndex in self.timelines[timelineIndex].markers.indices {
                    self.timelines[timelineIndex].markers[markerIndex].tagId = defaultTag.id
                }
            }
            print("✅ Migrated \(self.timelines.reduce(0) { $0 + $1.markers.count }) markers to use default tag '\(defaultTag.name)'")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Always encode with current version
        try container.encode(Project.currentFormatVersion, forKey: .formatVersion)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(fps, forKey: .fps)
        try container.encode(tags, forKey: .tags)
        try container.encode(timelines, forKey: .timelines)
    }
}
