# Text+ Style Gallery v1.1.0

v1.1.0 expands the static Shading styles that can be captured and reapplied in DaVinci Resolve Text+.

## Highlights

- Gradient Fill support, including multiple color stops.
- Gradient Mapping settings are preserved, including Angle, Size, Aspect, and Mapping Level.
- Image Shading can be captured and applied, including Mapping settings, Image Sampling, and Image Edge.
- Improved character-level Border Fill / Border Outline thumbnail representation.
- Reliable switching between Gradient and Solid styles.

## Gradient support

Gradient data is preserved using Fusion's native settings representation. Testing confirmed successful Capture → Apply for:

- Two-color gradients
- Three-color / multi-stop gradients
- Mapping Angle
- Mapping Size
- Mapping Aspect
- Mapping Level (Character / Text)

Gradient thumbnails are intended for identification rather than pixel-accurate reproduction. They use a representative color and a small gradient bar.

## Image Shading support

Testing confirmed successful Capture → Apply for external-image Text+ shading, including:

- External image file reference
- Mapping Angle
- Mapping Size
- Mapping Aspect
- Mapping Level
- Image Sampling
- Image Edge

### Important limitation

Image Shading stores a reference to the external image file path. The image itself is not embedded in the gallery JSON. If the source image is moved, renamed, deleted, or unavailable on another computer, the style settings can still be applied but the image cannot be displayed.

## Scope

Text+ Style Gallery focuses on reusable static appearance styles. Animation/keyframes, Follower, expressions, and Character Level Styling are not included in this release.

## Compatibility note

The existing behavior that preserves destination `StyledText` and protected layout/position values remains unchanged.
