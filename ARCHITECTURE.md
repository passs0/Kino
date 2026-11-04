# Serein — Architecture & Maintenance Guide

This document serves as the technical reference for future maintenance, enhancements, and contributions to **Serein**.

---

## 1. Core Architecture Overview

```
                      +-----------------------------+
                      |         User Input          |
                      |   (Local File / Web URL)    |
                      +--------------+--------------+
                                     |
                                     v
                       +---------------------------+
                       |     MediaCoordinator      |
                       +-------------+-------------+
                                     |
              +----------------------+----------------------+
              |                                             |
              v                                             v
     [Local File / Media]                         [Online Stream URL]
              |                                             |
              v                                             v
      FFprobeService (Probe)                        YtDlpService (Extract)
              |                                             |
              +----------------------+----------------------+
                                     |
                                     v
                       +---------------------------+
                       |    CompatibilityMatrix    |
                       +-------------+-------------+
                                     |
         +---------------------------+---------------------------+
         |                           |                           |
         v                           v                           v
  .directNative               .remuxOnly /                .fullTranscode /
  (AVPlayer 0% CPU)           .audioTranscodeOnly         .onlineTranscode
                              (Zero-Copy Local HLS)       (Apple Silicon VideoToolbox)
```

---

## 2. Directory Structure

```
Serein/
├── Package.swift                 # SPM manifest (CLI / Library mode)
├── Makefile                      # Make targets for build, clean, test
├── build_app.sh                  # Native compilation script via swiftc & codesign
├── Resources/
│   ├── Info.plist                # App bundle metadata, CFBundleURLTypes, UTI bindings
│   └── AppIcon.icns              # Multi-resolution macOS squircle application icon
├── Sources/
│   └── Serein/
│       ├── App/
│       │   ├── AppDelegate.swift       # Global key event monitors, file open handlers
│       │   └── SereinApp.swift         # SwiftUI App lifecycle, commands, menus
│       ├── Compatibility/
│       │   ├── CompatibilityMatrix.swift # Evaluates format, container & codecs
│       │   ├── FFmpegPipeline.swift    # Subprocess coordinator for local HLS server
│       │   ├── FFprobeService.swift    # JSON probe parsing for media streams
│       │   └── YtDlpService.swift      # Resolves online platforms & formats
│       ├── Coordinator/
│       │   ├── MediaCoordinator.swift  # Master state machine & log recorder
│       │   └── PlaybackStrategy.swift  # Playback modes and diagnostic labels
│       ├── Models/
│       │   ├── MediaSource.swift       # Enums for local vs. online sources
│       │   ├── PipelineStats.swift     # Real-time transcode FPS, speed, bitrate
│       │   ├── ProbeResult.swift       # Video/audio stream technical descriptors
│       │   └── SubtitleTrack.swift     # Cue parsing, position preservation & sanitization
│       ├── Player/
│       │   ├── CaptionAppearanceManager.swift # MediaAccessibility live system binding
│       │   ├── NativePlayerView.swift  # NSViewRepresentable wrapping AVPlayerLayer
│       │   ├── PlayerController.swift  # AVPlayer playback, seeking, volume, rate
│       │   └── SubtitleManager.swift   # Live cue matching & embedded VTT extraction
│       ├── Tools/
│       │   ├── PrerequisiteManager.swift # Automated 1-click engine downloader & updater
│       │   ├── ProcessRunner.swift     # Async Process execution with timeout
│       │   └── ToolLocator.swift       # Multi-path search for ffmpeg, ffprobe, yt-dlp
│       └── Views/
│           ├── MainWindowView.swift    # Liquid glass window wrapper & sheets
│           ├── MediaInspectorView.swift# Technical HUD (⌘I) for stream metrics
│           ├── OptionsMenuPresenter.swift # Native AppKit options popup menu (...)
│           ├── PrerequisiteInstallSheet.swift # 1-click helper engine downloader sheet
│           ├── ToolStatusView.swift    # Dependency inspector popover
│           ├── URLInputSheet.swift     # Online URL input sheet (⌘U)
│           └── VideoPlayerView.swift   # Canvas, controls overlay, responsive subtitles
```

---

## 3. Key Subsystems & Design Choices

### A. PrerequisiteManager & On-Demand Engines
- **Location**: Helper binaries are installed into `~/Library/Application Support/Serein/bin/`.
- **Search Order**:
  1. `~/Library/Application Support/Serein/bin/` (Managed)
  2. `/opt/homebrew/bin/` (Homebrew ARM64)
  3. `/usr/local/bin/` (Homebrew Intel)
  4. Standard `$PATH`
- **Integrity**: Keeping helper binaries in user Application Support avoids breaking Gatekeeper code signatures on `Serein.app` when updating `yt-dlp` (`yt-dlp -U`).

### B. Subtitles & MediaAccessibility
- Subtitle visual appearance adheres strictly to macOS system accessibility settings via `MediaAccessibility` framework (`MACaptionAppearanceCopy*`).
- Non-position styling (custom fonts, colors, borders) from ASS/SSA is stripped to maintain system consistency.
- Semantic vertical positioning (`\an8`, `\an7`, `\pos`, `line:10%`) is preserved to prevent top/middle title subtitles from overlapping bottom dialogue.
- Subtitle sizing dynamically scales with window height ($18\text{pt}$ to $48\text{pt}$) in full screen.

### C. Playback Pipeline & Zero-Copy Remux
- When playing `.mkv` or `.webm` files containing native H.264/HEVC video, `FFmpegPipeline` uses `-c:v copy` to repackage streams into fragmented HLS on a local loopback HTTP server. This achieves `< 100ms` startup latency with **0% video re-encoding CPU load**.
- When online CDN links reject direct AVPlayer requests with HTTP 403 Forbidden, Serein pipes `yt-dlp` output directly into `ffmpeg` stdin to authenticate and stream simultaneously.

---

## 4. Maintenance Commands

```bash
# Build Serein.app
./build_app.sh

# Run clean build
rm -rf build /tmp/swift-cache && ./build_app.sh

# Re-install to system Applications
cp -R build/Serein.app /Applications/
xattr -cr /Applications/Serein.app
codesign --force --deep --sign - /Applications/Serein.app
touch /Applications/Serein.app

# Package release archive
cd build && zip -r -y -9 ../Serein-v0.1.1-macOS.zip Serein.app && cd ..
```
