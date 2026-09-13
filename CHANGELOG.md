# Changelog

All notable changes to Text+ Style Gallery are documented here.

## [1.1.0] - 2026-09-13

### Added
- Extended Text+ Shading support, including Gradient fills.
- Gradient capture/apply for multiple color stops.
- Gradient Mapping settings including Angle, Size, Aspect, and Mapping Level.
- Image Shading capture/apply using external image file references.
- Image Shading settings including Mapping Angle, Size, Aspect, Mapping Level, Image Sampling, and Image Edge.
- Improved thumbnail representation for character-level Border Fill / Border Outline.
- Gradient thumbnails now use a representative color plus a small gradient indicator bar for easier identification.

### Fixed
- Correctly restores the Shading `TypeN` when switching between Gradient and Solid styles, so applying a Solid style after a Gradient works reliably.
- Preserved native Fusion Gradient data by applying `ShadingGradientN` through `SaveSettings()` / `LoadSettings()` rather than attempting to recreate Gradient userdata with `SetInput()`.

### Notes
- Gradient thumbnails are intentionally approximate and do not reproduce Resolve's final rendered Gradient exactly.
- Image Shading thumbnails do not reproduce the source image exactly.
- Image Shading stores the external image file path. Moving, renaming, or deleting the referenced image can cause the image to be unavailable when the style is applied. Exporting the JSON alone does not package the referenced image file.
- Animation, keyframes, Follower, expressions, and Character Level Styling are outside the scope of the style gallery.

## [1.0.3]

### Changed
- Improved style application performance by batching Text+ input updates with Fusion composition Lock/Unlock.
- Kept Shading Element bootstrap operations outside the composition lock for compatibility.
- Corrected the Clip Color list to match DaVinci Resolve.

## [1.0.2]

### Changed
- Made the gallery window more compact.
- Reduced thumbnail and control sizes while keeping the 10-slot page layout.

## [1.0.1]

### Fixed
- Fixed Shading Element initialization for elements whose detailed inputs had not yet been instantiated by Resolve.
- Missing Shading Elements are bootstrapped before their captured settings are applied.

## [1.0.0]

- Initial public release.
- 100 style slots organized as 10 pages of 10.
- Capture and apply Text+ styles while preserving the destination text content.
- Apply styles to the current clip, selected video track, or clips filtered by clip color.
- JSON import/export.
- SVG thumbnail previews.
