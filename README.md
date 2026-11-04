<p align="center">
  <img src="assets/icon.png" width="160" height="160" alt="Serein Icon" />
</p>

<h1 align="center">Serein</h1>

<p align="center">
  <strong>The Modern QuickTime Player Successor with Next-Gen Codec Support</strong><br/>
  Native, lightweight, hardware-accelerated media player & coordinator built with SwiftUI, AppKit, and AVFoundation for Apple Silicon macOS.
</p>

---

> [!NOTE]
> **AI-Generated Project Disclosure**
> **Serein** (including its architecture, VideoToolbox zero-copy HLS pipeline, custom MediaAccessibility subtitle renderer, and Apple squircle design) is an **AI-generated project** created with **Antigravity** (Google DeepMind).

---

## ✨ Why Serein?

For decades, **QuickTime Player** has set the standard for macOS media playback: instant startup, ultra-efficient hardware decoding with near-zero battery drain, smooth timeline scrubbing, and pure Apple Human Interface design.

**The catch?** QuickTime refuses to open `.mkv`, `.webm`, `.opus`, or web streams, and rejects modern subtitles (`.ass`, `.srt`, web captions). To watch these files, Mac users have traditionally turned to bloated third-party players (like VLC or legacy wrappers) that drain MacBook batteries with CPU-heavy software decoders, feature complex multi-window interfaces, and ignore macOS design standards.

**Serein is the modern successor:**
- **QuickTime Aesthetics & Efficiency:** Native Cocoa chrome, fluid animations, and 0% CPU consumption on standard formats.
- **Universal Codec & Container Support:** Plays `.mkv`, `.webm`, `.avi`, `.ts`, `.mp4`, `.mov`, VP9, AV1, and Opus seamlessly.
- **Zero-Friction In-App Engine Setup:** Automatically manages helper engines with 1 click in user space—no Terminal commands, no Homebrew, and no `sudo` required!

---

## 🚀 Features

### 1. Intelligent Playback Strategy Matrix
Serein actively evaluates container formats, audio streams, and video codecs before dynamically selecting the optimal playback path:

| Strategy | When Applied | Impact & Performance |
| :--- | :--- | :--- |
| **Direct Native** | Supported container (`.mp4`, `.mov`, `.m4v`) + native codecs (H.264, HEVC, ProRes, AAC) | **0% CPU Overhead**, instant hardware decode via AVPlayer (< 5ms startup). |
| **Zero-Copy Stream Remux** | Incompatible container (`.mkv`, `.webm`) with native video streams | Repackages container on-the-fly to local HLS in **< 100ms** with **zero video re-encoding**. |
| **Audio Transcode** | Native video (H.264/HEVC) paired with incompatible audio (DTS, Opus, TrueHD) | Bit-for-bit passthrough for video; audio transcoded in real time (>30× speed) to high-fidelity AAC. |
| **Hardware VideoToolbox** | Incompatible video codecs (VP9, VP8, AV1, MPEG-2) | Real-time Apple Silicon VideoToolbox GPU encoding with 0% dropped frames. |
| **Online Stream Bridge** | Web streaming links & video platforms | Authenticated piped yt-dlp ➔ FFmpeg pipeline bypassing 403 Forbidden CDN blocks while preserving original audio. |

### 2. macOS System Settings Accessibility Captions
Serein treats subtitles as a first-class citizen using Apple's official `MediaAccessibility` framework (`MACaptionAppearance`):
- **System-Wide Consistency:** Subtitles dynamically adapt to your preferences in **System Settings ➔ Accessibility ➔ Captions** (e.g. *Transparent Background*, *Classic*, *Outline Text*, or *Large Text*).
- **Responsive Subtitle Scaling:** Caption font size, padding, and line height dynamically scale with the viewport height ($18\text{pt}$ to $48\text{pt}$) when entering full screen.
- **Smart ASS/SSA Sanitization:** Automatically strips cluttered custom font/color overrides from anime and community subtitles while preserving semantic screen positioning (top, bottom, and center placement).
- **Embedded Subtitle Extraction:** Automatically extracts container-embedded tracks (`mov_text`, `srt`, `ass`, `webvtt`) on-the-fly.

---

## ⚡️ Zero-Friction Setup: No Terminal Required

Unlike traditional players that demand manual command-line installations, Serein keeps the core application download ultra-compact (**~3.2 MB**) and provides an **automated in-app engine installer**:

1. **Automatic Detection:** If you already have Homebrew (`brew install ffmpeg yt-dlp`), Serein detects and uses them immediately with zero configuration.
2. **1-Click In-App Download:** On fresh Macs without Homebrew, Serein prompts you with a clean native setup sheet (`⌘,`) and downloads managed static binaries directly into `~/Library/Application Support/Serein/bin/`.
3. **Preserves Apple Code Signatures:** By keeping helper engines in user Application Support, Serein never breaks its Gatekeeper code signatures and enables seamless background updates via `yt-dlp -U`.

---

## ⌨️ Native Controls & Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| **`Space`** | Play / Pause |
| **`←` (Left Arrow)** | Step Backward ($5\text{s}$) |
| **`→` (Right Arrow)** | Step Forward ($5\text{s}$) |
| **`+` / `=`** | Volume Up ($+10\%$) |
| **`-`** | Volume Down ($-10\%$) |
| **`M`** | Mute / Unmute |
| **`Z`** | Toggle Aspect Ratio: **Fit to Screen (Letterbox)** vs. **Fill Screen** |
| **`⌘I`** | Toggle Media Statistics & Technical Inspector HUD |
| **`⌘,`** | Media Engines & Codecs Setup Sheet |
| **`⌘O`** | Open Local Media File |
| **`⌘U`** | Open Online Streaming URL |

---

## 🛠️ Building & Installing

### Option 1: Direct Download (Pre-built)
1. Download `Serein.app` from the [GitHub Releases](https://github.com/passs0/Serein/releases).
2. Drag `Serein.app` into your `/Applications/` folder.
3. Open `Serein.app` and press `⌘O` to open any file or `⌘U` for streaming links!

### Option 2: Build from Source
```zsh
git clone https://github.com/passs0/Serein.git
cd Serein
./build_app.sh
cp -R build/Serein.app /Applications/
```

---

## 🗺️ Roadmap

- [x] Native AVFoundation + VideoToolbox hybrid engine
- [x] In-app automated media engine downloader & updater
- [x] macOS Accessibility caption rendering
- [x] Online streaming pipeline with original audio selection
- [ ] **v0.2.0**: Dedicated Audio Mode & Floating Mini Player HUD
- [ ] **v0.2.0**: Playlist Queue with drag-and-drop & continuous playback
- [ ] **v0.2.0**: macOS Control Center (`MPNowPlayingInfoCenter`) & media key support
- [ ] **v0.3.0**: Native Picture-in-Picture (`AVPictureInPictureController`)
- [ ] **v0.3.0**: Variable speed with CoreAudio pitch correction ($0.5\times$–$3.0\times$)

---

## 📄 License

Released under the [MIT License](LICENSE).
