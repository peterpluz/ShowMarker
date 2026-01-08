# ShowMarker — Architecture

## Overview

ShowMarker is a document-based iOS application.
Each project is stored as a single `.smark` file.

The application uses SwiftUI `DocumentGroup` with
`ReferenceFileDocument` as the document layer.

The document layer is the single source of truth for all project data.

---

## File Format: `.smark`

`.smark` is a JSON-based file format.

The root object of the file is **ProjectFile**.

Direct serialization of `Project` is forbidden.

---

## ProjectFile

```json
{
  "formatVersion": 1,
  "project": { ... }
}
