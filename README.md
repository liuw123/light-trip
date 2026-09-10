# Light Trip

Light Trip is an offline-first SwiftUI trip companion for iPhone and iPad. It turns a strict, versioned JSON contract—or a best-effort Markdown itinerary—into a glanceable timeline, booking library, original-plan reader, and local reminders.

## MVP

- iOS and iPadOS 17+
- SwiftUI and SwiftData
- No third-party dependencies
- Strict Light Trip JSON import, review, persistence, and export
- Deterministic local Markdown import, including English and common Chinese headings
- Timeline, activity, booking, source, settings, and editor screens
- Explicit clipboard access and file import
- Local notifications for activity reminders
- Adaptive compact and regular-width navigation
- Unit and UI test targets

Cost, budget, payment, live booking status, cloud parsing, and YAML are intentionally outside the MVP.

## Run

1. Open `LightTrip.xcodeproj` in Xcode 16 or newer.
2. Select an iPhone or iPad simulator running iOS 17 or newer.
3. Set your development team and a unique bundle identifier if running on a physical device.
4. Run the `LightTrip` scheme.

The empty state includes a bundled sample trip that exercises JSON import without requiring clipboard access.

## Contract

- Product and architecture: [`docs/design.md`](docs/design.md)
- Normative JSON Schema: [`docs/schema/light-trip.schema.json`](docs/schema/light-trip.schema.json)
- JSON example: [`docs/examples/sample-trip.lighttrip.json`](docs/examples/sample-trip.lighttrip.json)
- Markdown example: [`docs/examples/sample-trip.md`](docs/examples/sample-trip.md)

Unknown additive JSON properties are accepted for forward compatibility, while version, required fields, enum values, identifiers, dates, time ranges, relationships, and timezones are validated before Import Review.

## Tests

Run unit and UI tests from Xcode with Product → Test, or from a macOS command line:

```sh
xcodebuild -project LightTrip.xcodeproj \
  -scheme LightTrip \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test
```

The repository intentionally does not commit signing credentials or a development-team identifier.
