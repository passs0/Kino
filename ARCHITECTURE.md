# Kino — Architecture & Maintenance Guide

This document serves as the technical reference for future maintenance, enhancements, and contributions to **Kino**.

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
Kino/
├── LICENSE                       # MIT License
├── Package.swift                 # SPM manifest
├── Makefile                      # Make targets for build, clean, test, dmg
├── build_app.sh                  # Native compilation script via swiftc & codesign
├── assets/
│   └── icon.png                  # 512x512 README application icon
├── Resources/
│   ├── Info.plist                # App bundle metadata & UTI document bindings
│   └── AppIcon.icns              # Multi-resolution macOS squircle application icon
├── Sources/
│   └── Kino/
│       ├── main.swift                  # Application entry point
│       ├── App/
│       │   ├── AppDelegate.swift       # Global key event monitors, file open handlers
│       │   └── KinoApp.swift           # SwiftUI App lifecycle, commands, menus
│       ├── Compatibility/
│       │   ├── FFmpegPipeline.swift    # Subprocess coordinator for local HLS server
│       │   ├── FFprobeService.swift    # JSON probe parsing for media streams
│       │   ├── LocalStreamingServer.swift # Loopback (127.0.0.1) HTTP 1.1 HLS server
│       │   └── YtDlpService.swift      # Resolves online platforms & formats
│       ├── Coordinator/
│       │   ├── CompatibilityMatrix.swift # Evaluates format, container & codecs
│       │   └── MediaCoordinator.swift  # Master state machine & log recorder
│       ├── Models/
│       │   ├── CodecTypes.swift        # Video and audio codec descriptors
│       │   ├── ContainerFormat.swift   # Media container classification
│       │   ├── MediaProbeResult.swift  # Video/audio/subtitle stream descriptors
│       │   ├── MediaSource.swift       # Enums for local vs. online sources
│       │   ├── PlaybackStrategy.swift  # Playback modes and diagnostic labels
│       │   └── SubtitleTrack.swift     # ASS/WebVTT/SRT cue parsing & position extraction
│       ├── Player/
│       │   ├── CaptionAppearanceManager.swift # MediaAccessibility live system binding
│       │   ├── NativePlayerView.swift  # NSViewRepresentable wrapping AVPlayerLayer & PiP
│       │   ├── PlayerController.swift  # AVPlayer playback, seeking, volume, rate
│       │   ├── PlayerTimeState.swift   # Decoupled high-frequency timeline state
│       │   └── SubtitleManager.swift   # Live cue matching & embedded ASS/VTT extraction
│       ├── Tools/
│       │   ├── PrerequisiteManager.swift # Automated 1-click engine downloader & updater
│       │   ├── ProcessRunner.swift     # Async Process execution with streaming pipes
│       │   └── ToolLocator.swift       # Multi-path search for ffmpeg, ffprobe, yt-dlp
│       └── Views/
│           ├── LiquidGlass.swift       # macOS Liquid Glass transport & button primitives
│           ├── MainWindowView.swift    # Main window wrapper & modal sheets
│           ├── MediaInspectorView.swift# Technical HUD (⌘I) for stream metrics
│           ├── OptionsMenuPresenter.swift # Native AppKit options popup menu (...)
│           ├── PrerequisiteInstallSheet.swift # 1-click helper engine downloader sheet
│           ├── TrafficLightManager.swift # macOS 26 squircle titlebar & traffic light alignment
│           ├── URLInputSheet.swift     # Online URL input sheet (⌘U)
│           └── VideoPlayerView.swift   # Canvas, controls overlay, responsive subtitles
└── Tests/
    └── RunTests.swift            # Engine & compatibility matrix test suite
```

---

## 3. Key Subsystems & Design Choices

### A. PrerequisiteManager & On-Demand Engines
- **Location**: Helper binaries are installed into `~/Library/Application Support/Kino/bin/`.
- **Search Order**:
  1. `~/Library/Application Support/Kino/bin/` (Managed)
  2. `/opt/homebrew/bin/` (Homebrew ARM64)
  3. `/usr/local/bin/` (Homebrew Intel)
  4. Standard `$PATH`
- **Integrity**: Keeping helper binaries in user Application Support avoids breaking Gatekeeper code signatures on `Kino.app` when updating `yt-dlp` (`yt-dlp -U`).

### B. Subtitles & MediaAccessibility
- Subtitle visual appearance adheres strictly to macOS system accessibility settings via `MediaAccessibility` framework (`MACaptionAppearanceCopy*`).
- Non-position styling (custom fonts, colors, borders) from ASS/SSA is stripped to maintain system consistency.
- Semantic vertical positioning (`Style:` alignment, `\an8`, `\an7`, `\pos`, `line:10%`) is preserved to prevent top/middle title subtitles from overlapping bottom dialogue.
- Subtitle sizing dynamically scales with window height (`18 pt` to `48 pt`) in full screen.

### C. Playback Pipeline & Zero-Copy Remux
- When playing `.mkv` or `.webm` files containing native H.264/HEVC video, `FFmpegPipeline` uses `-c:v copy` to repackage streams into fragmented HLS on a local loopback (`127.0.0.1`) HTTP server. This achieves `< 100ms` startup latency with **0% video re-encoding CPU load**.
- When online CDN links reject direct AVPlayer requests with HTTP 403 Forbidden, Kino pipes `yt-dlp` output directly into `ffmpeg` stdin to authenticate and stream simultaneously.

---

## 4. Maintenance Commands

```zsh
# Build Kino.app
./build_app.sh

# Run clean build
rm -rf build /tmp/swift-cache && ./build_app.sh

# Re-install to system Applications
cp -R build/Kino.app /Applications/
xattr -cr /Applications/Kino.app
codesign --force --deep --sign - /Applications/Kino.app
touch /Applications/Kino.app
```
