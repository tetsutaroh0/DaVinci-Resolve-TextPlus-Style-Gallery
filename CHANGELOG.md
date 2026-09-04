# Changelog

All notable public changes to Text+ Style Gallery will be documented here.

## v1.0.2 - 2026-09-04

### Changed

- Reduced the gallery window width for a more compact layout.
- Kept thumbnail previews at the same size.
- Shortened the style-name input fields.
- Shortened the JSON filename input field.
- Slightly compacted the top filter controls.
- Adjusted the final window width so the Capture and Delete buttons remain fully visible.
## v1.0.1 - 2026-09-04

### Fixed

- Fixed an issue where some Shading Elements, especially shadows, were not fully applied on the first click.
- Shading Elements that have not yet been instantiated by DaVinci Resolve are now initialized before their properties are applied.
- Styles containing previously unused Shading Elements now apply correctly with a single click.
## [1.0.0] - 2026-09-04

### Initial public release

- 10 pages × 10 slots for 100 Text+ styles
- Generic Text+ style capture
- Safe style application while preserving `StyledText`
- Multiple Shading Element capture/application
- Fill, outline and shadow-aware SVG thumbnail previews
- Apply targeting by current clip, video track and clip color
- JSON import/export
- Per-user data storage
- Native Lua implementation with no Python/Pillow requirement
- Cached thumbnails and in-place page updates for fast Prev/Next navigation
- Compact 770 × 790 gallery layout
