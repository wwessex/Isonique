# Isonique processing alternatives

This engineering note records the 8 November 2026 processing review. See the [test results](docs/TEST_RESULTS.md) for later RAW validation. The current app uses independent, source-defined pixel equations; it does not recover or reproduce Apple's proprietary RAW engine. Camera RAW decoding still uses Apple ImageIO. No third-party engine listed below is bundled or claimed to work in this build.

## Candidates

| Option | Role | Licence reported upstream | Fit and remaining work |
| --- | --- | --- | --- |
| [LibRaw](https://www.libraw.org/docs) | Read camera RAW files and produce decoded sensor/conversion data | LGPL 2.1 or CDDL 1.0 | Recommended RAW candidate: its C API can be bridged into Swift. Requires a pinned native build, decoder wrapper, orientation/white balance/color handling, full-resolution rather than embedded-preview verification, camera fixtures and redistribution notices. |
| [libvips](https://www.libvips.org/) | Arithmetic, convolution, color conversion and resampling with demand-driven processing | LGPL 2.1 or later | Recommended candidate for larger-image processing: native C API and low-memory design. Requires an arm64 build, Swift bridge, color/alpha tests and packaging of codec dependencies. It does not by itself establish Aperture RAW fidelity. |
| [OpenImageIO](https://github.com/AcademySoftwareFoundation/OpenImageIO) | Format-independent image I/O and processing, aimed at VFX | Apache 2.0 | Broader alternative if high-bit-depth formats and a larger native dependency stack become necessary. Not selected for this small Swift-only build. Review all enabled plug-ins and their dependency licences separately. |

The recommendation is an engineering assessment of those documented capabilities, not a camera-compatibility or performance result. No library or package was downloaded, linked or benchmarked during this change.

## Implemented now

`Sources/IsoniqueCore/Library.swift`, `Renderer.render`, always uses the existing independent CPU implementation for both preview and export, replacing the previous Core Image adjustment path. This removes dependence on opaque Core Image exposure/color-control equations. Decoding, color-space conversion, resizing and geometry still use Apple ImageIO/Core Graphics; this is not an entirely open-source imaging stack.

The pipeline decodes into premultiplied 8-bit sRGB, unpremultiplies each nonzero-alpha pixel, applies the equations below, clamps channels into [0,1], then premultiplies and rounds to bytes. Transparent pixels remain transparent. Exposure/color and tone use separate byte passes. Geometry follows tone. Preview downsampling precedes edits, so differently sized previews and JPEG exports need not be byte-identical.

- sRGB decoding: `L = c/12.92` when `c <= 0.04045`, otherwise `((c+0.055)/1.055)^2.4`.
- Exposure: multiply linear `L` by `2^EV`, then encode to sRGB with `12.92*L` when `L <= 0.0031308`, otherwise `1.055*L^(1/2.4)-0.055`.
- Saturation: in encoded sRGB, `Y = 0.2126*r + 0.7152*g + 0.0722*b`; `c = Y + (c-Y)*saturation`.
- Contrast: `c = (c-0.5)*contrast + 0.5`.
- White balance is an artistic channel gain, not calibrated camera temperature. Clamp warmth/tint into [-1,1] and multiply by 0.15, giving `w,t`. RGB gains are `1+w+t/2`, `1-t`, `1-w+t/2`.
- Tone uses encoded-sRGB luma `Y` before channel gains. With shadows `s` clamped into [0,1] and highlights `h` into [-1,0], add `s*(1-Y)^2*Y + h*Y^2*(1-Y)` to each balanced channel.

The independent tone, saturation and contrast equations are product choices, not recovered Aperture formulas or a physically calibrated RAW development pipeline. Tests check the public renderer against known sRGB middle-gray values at neutral and ±1 EV, existing tone direction checks, geometry, JPEG export, persistence and unchanged original hashes.

## Compatibility and limits

Existing catalogues and adjustment values are retained. The [library compatibility notes](COMPATIBILITY.md) explain how Isonique finds earlier libraries. Output can differ from earlier Core Image renders, although originals are never changed. The current 8-bit path clips highlights and is unsuitable for preserving scene-linear HDR or full sensor precision. A production RAW replacement should keep float/high-bit-depth data until display/export and validate real RAW files from each supported camera before advertising support.

Only the native arm64 macOS app exists here. There are no maintained web/PWA or separate mobile variants. Intel, older macOS runtimes and a LibRaw-backed decoder have not been validated.
