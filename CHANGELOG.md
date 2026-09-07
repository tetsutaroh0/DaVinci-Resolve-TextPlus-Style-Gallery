# Changelog

## v1.0.3 - 2026-09-07

### Changed

- Significantly improved style-application performance, especially when applying a style to multiple Text+ clips.
- Batched Text+ input updates while the Fusion composition is locked, reducing unnecessary intermediate evaluations.
- Updated the Clip Color Filter to match DaVinci Resolve clip colors: Orange, Apricot, Yellow, Lime, Olive, Green, Teal, Navy, Blue, Purple, Violet, Pink, Tan, Beige, Brown, and Chocolate.

### Compatibility

- The v1.0.1 Shading Element initialization fix is retained.
- Style application continues to preserve the destination `StyledText` and protected layout values.
- No changes were made to the style library format.
- Existing saved style libraries remain compatible.

## v1.0.2 - 2026-09-04

### Changed

- Reduced the gallery window width for a more compact layout.
- Kept thumbnail previews at the same size.
- Shortened the style-name input fields.
- Shortened the JSON filename input field.
- Slightly compacted the top filter controls.
- Adjusted the final window width so the Capture and Delete buttons remain fully visible.

### Compatibility

- No functional changes were made to style capture or style application.
- Existing saved style libraries remain compatible.

## v1.0.1 - 2026-09-04

### Fixed

- Fixed an issue where some Shading Elements, especially shadows, were not fully applied on the first click.
- Shading Elements that have not yet been instantiated by DaVinci Resolve are now initialized before their properties are applied.
- Styles containing previously unused Shading Elements now apply correctly with a single click.

### Compatibility

- No changes were made to the style library format.
- Existing saved style libraries from v1.0.0 remain compatible.

## v1.0.0 - 2026-09-04

### Initial public release

- 10 pages x 10 slots for 100 Text+ styles
- Generic Text+ style capture
- Safe style application while preserving `StyledText`
- Multiple Shading Element capture/application
- Fill, outline and shadow-aware SVG thumbnail previews
- Apply targeting by current clip, video track and clip color
- JSON import/export
- Per-user data storage
- Native Lua implementation with no Python/Pillow requirement
- Cached thumbnails and in-place page updates for fast Prev/Next navigation
- Compact gallery layout
