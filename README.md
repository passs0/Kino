<p align="center">
  <img src="assets/icon_mac.png" width="160" height="160" alt="Kino Icon" />
</p>

<h1 align="center">Kino</h1>

<p align="center">
  <strong>The Modern QuickTime Player Successor with Next-Gen Codec Support</strong><br/>
  Native, hardware-accelerated media player built with SwiftUI, AppKit, and AVFoundation for Apple Silicon macOS.
</p>

<p align="center">
  <a href="https://github.com/passs0/Kino/releases/latest"><img src="https://img.shields.io/github/v/release/passs0/Kino?label=Latest%20Release&color=007AFF" alt="Latest Release" /></a>
  <img src="https://img.shields.io/badge/macOS-13.0%2B%20%7C%20Apple%20Silicon-black?logo=apple" alt="macOS 13.0+" />
  <img src="https://img.shields.io/badge/framework-SwiftUI%20%7C%20AppKit%20%7C%20AVFoundation-blue" alt="Frameworks" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License" /></a>
</p>

<p align="center">
  <img src="assets/preview.png" width="640" alt="Kino Welcome Screen" />
</p>

---

> [!NOTE]
> **AI-Generated Project Disclosure**
> **Kino** (including its VideoToolbox zero-copy HLS pipeline, subtitle renderer, and Apple squircle design) is an **AI-generated project** created with **Antigravity** (Google DeepMind).

---

## Features

- **QuickTime Aesthetics & Zero-Bloat Footprint:** Native Cocoa floating HUD bar, Fluid Letterboxing, document proxy icon, and macOS 26+ Liquid Glass controls with native material fallbacks on macOS 13–15.
- **Universal Format & Stream Support:** Plays `.mkv`, `.webm`, `.avi`, `.ts`, `.mp4`, `.mov`, `.flac`, `.alac`, VP9, AV1, Opus, and web streams (`yt-dlp` + `ffmpeg` auto-setup in user space—no Homebrew required).
- **Apple MetalFX & CoreImage GPU Upscaling:** Built-in `MetalFX` Spatial Super-Resolution, luminance sharpening, edge enhancement, and bilateral noise reduction running directly in the GPU compositor.
- **Discrete Surround & Dolby Atmos:** Preserves 5.1/7.1 surround tracks, E-AC-3 JOC Spatial Audio, and Dolby TrueHD/MLP decoding.
- **First-Class Subtitle Engine:** Native OpenSubtitles.com search (`⌥⌘S`) with `MovieHash` exact sync, real-time delay controls (`G` / `H`), sidecar auto-discovery, drag-and-drop subtitles, and System Accessibility caption styling.
- **Control Center & Unified Audio Mode:** Full `MPNowPlayingInfoCenter` integration, lossless `.flac`/`.alac` playback with embedded cover art wash, and Always-On-Top pinning (`⌥⌘P`).

## Playback Strategy Matrix

| Strategy | When Applied | Performance |
| :--- | :--- | :--- |
| **Direct Native** | Native containers (`.mp4`, `.mov`) + H.264/HEVC/ProRes | **0% CPU**, instant `AVPlayer` hardware decode |
| **Zero-Copy Remux** | `.mkv`, `.webm` with native video streams | Local HLS repackage in `< 100ms`, zero video re-encode |
| **Audio Transcode** | Native video + DTS, Opus, or TrueHD audio | Video passthrough; real-time AAC audio transcode |
| **VideoToolbox GPU** | VP9, VP8, AV1, MPEG-2 video | Real-time Apple Silicon hardware transcode |
| **Online Stream Bridge** | Web URLs & video platforms | Piped `yt-dlp` ➔ `FFmpeg` stream bridge |

## Installation

### Download Release
1. Download **`Kino-v1.1.1.dmg`** from [GitHub Releases](https://github.com/passs0/Kino/releases/latest) and drag **`Kino.app`** to `/Applications`.
2. On first launch, right-click `Kino.app` ➔ **Open**, or run `xattr -cr /Applications/Kino.app`.

### Build from Source
```zsh
git clone https://github.com/passs0/Kino.git && cd Kino
./build_app.sh
cp -R build/Kino.app /Applications/
```

## License

Released under the [MIT License](LICENSE).
