# Serein — Native macOS Hardware-Accelerated Video Player

**Serein** is a lightweight, hardware-accelerated video player and media coordinator built natively for macOS with **SwiftUI**, **AppKit**, and **AVFoundation**.

It bridges modern media formats with Apple's high-efficiency hardware decoders by actively evaluating container formats, video codecs, and audio streams to select the optimal playback strategy.

---

## ⚡️ Prerequisites

To build and run Serein on macOS, ensure the following prerequisites are installed:

- **macOS Version**: macOS 15.0+ (Sequoia or later)
- **Architecture**: Apple Silicon (M1/M2/M3/M4) recommended for hardware VideoToolbox acceleration
- **Developer Tools**: Xcode Command Line Tools (`swiftc`, `codesign`, `iconutil`)
- **CLI Streaming Dependencies** (install via Homebrew):
  ```bash
  brew install ffmpeg yt-dlp
  ```
  - `ffmpeg` & `ffprobe`: Container inspection, zero-copy HLS remuxing, and on-the-fly subtitle extraction.
  - `yt-dlp`: Stream resolution and authenticated media extraction for online platforms.

---

## 🚀 Key Features

### 1. Intelligent Playback Strategy Matrix
| Strategy | When Applied | Impact |
| :--- | :--- | :--- |
| **Direct Native** | Supported container (`.mp4`, `.mov`, `.m4v`) + native codecs (H.264, HEVC, AAC) | **0% CPU**, instant launch (< 5ms) |
| **Stream Copy Remux** | Incompatible container (`.mkv`, `.webm`, cloud streams) with native streams | **Zero video re-encoding**, repackages on-the-fly to local HLS in < 100ms |
| **Audio Transcode** | Native video (H.264/HEVC) + incompatible audio (DTS, Opus, TrueHD) | Bit-for-bit video copy, audio converted in real-time (>30x speed) to high-fidelity AAC |
| **Hardware VideoToolbox** | Incompatible video codecs (VP9, VP8, AV1, MPEG-2) | Real-time Apple Silicon VideoToolbox GPU encoding with 0% dropped frames |
| **Online Stream Bridge** | Web streaming links | Piped yt-dlp ➔ FFmpeg pipeline eliminating 403 Forbidden errors and selecting original audio |

### 2. Native System Settings Accessibility Captions
- Fully integrated with Apple's `MediaAccessibility` framework (`MACaptionAppearance`).
- Subtitles automatically match your preferences in **System Settings ➔ Accessibility ➔ Captions** (e.g. *Transparent Background*, *Classic*, or *Large Text*), dynamically adapting corner radii, translucent backdrops, text drop shadows, and font scaling in real time.
- Embedded subtitle streams (`mov_text`, `srt`, `ass`, `subrip`, `webvtt`) are extracted and parsed on-the-fly in the background.

### 3. Keyboard Shortcuts & Controls
- **`Space`**: Play / Pause toggle
- **`←` (Left Arrow)**: Step backward ($5\text{s}$)
- **`→` (Right Arrow)**: Fast forward ($5\text{s}$)
- **`+` / `=`**: Increase volume ($+10\%$)
- **`-`**: Decrease volume ($-10\%$)
- **`M`**: Mute / Unmute
- **`Z`**: Toggle Aspect Ratio (Letterbox Fit vs. Fill Screen)
- **`⌘I`**: Toggle Media Statistics & Technical Inspector
- **`⌘O`**: Open Local File
- **`⌘⇧O`**: Open Online Stream URL

### 4. Apple Built-in Design Language
- Clean macOS continuous squircle icon styled after Apple's built-in media players.
- Minimalist window chrome with solid macOS native background and floating transport bar.
- Native AppKit options menu (`...` button) for instantaneous subtitle and playback speed selection (0.5x – 2.0x).

---

## 📦 Building from Source

```bash
# Clone the repository
git clone https://github.com/passs0/Serein.git
cd Serein

# Build and sign Serein.app
./build_app.sh

# Launch the app
open build/Serein.app
```

---

## 📄 License

MIT License. Designed with Apple Human Interface Guidelines for macOS.
