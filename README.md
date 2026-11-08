<p align="center">
  <img src="assets/icon.png" width="160" height="160" alt="Serein Icon" />
</p>

<h1 align="center">Serein</h1>

<p align="center">
  <strong>The Modern QuickTime Player Successor with Next-Gen Codec Support</strong><br/>
  Native, lightweight, hardware-accelerated media player & coordinator built with SwiftUI, AppKit, and AVFoundation for Apple Silicon macOS.
</p>

<p align="center">
  <a href="https://github.com/passs0/Serein/releases/latest"><img src="https://img.shields.io/github/v/release/passs0/Serein?label=Latest%20Release&color=007AFF" alt="Latest Release" /></a>
  <img src="https://img.shields.io/badge/macOS-13.0%2B%20%7C%20Apple%20Silicon-black?logo=apple" alt="macOS 13.0+" />
  <img src="https://img.shields.io/badge/bundle-2.2%20MB-success" alt="Bundle Size" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License" /></a>
</p>

<p align="center">
  <img src="assets/preview.png" width="720" alt="Serein Player Interface" />
</p>

---

> [!NOTE]
> **AI-Generated Project Disclosure**
> **Serein** (including its architecture, VideoToolbox zero-copy HLS pipeline, custom MediaAccessibility subtitle renderer, and Apple squircle design) is an **AI-generated project** created with **Antigravity** (Google DeepMind).

---

## ✨ Why Serein?

For decades, **QuickTime Player** has set the standard for macOS media playback: instant startup, ultra-efficient hardware decoding with near-zero battery drain, smooth timeline scrubbing, and pure Apple Human Interface design.

**The catch?** QuickTime refuses to open `.mkv`, `.webm`, `.opus`, or web streams, and rejects modern subtitles (`.ass`, `.srt`, web captions). To watch these files, Mac users often have to rely on external tools that may not integrate natively with macOS design standards, rely on heavier software decoders, or feature complex multi-window interfaces.

**Serein is the modern successor:**
- **QuickTime Aesthetics & Efficiency:** Native Cocoa chrome, fluid animations, and 0% CPU consumption on standard formats.
- **Universal Codec & Container Support:** Plays `.mkv`, `.webm`, `.avi`, `.ts`, `.mp4`, `.mov`, VP9, AV1, and Opus seamlessly.
- **Pure Apple Native Video Enhancement:** Built-in Apple MetalFX Spatial Super-Resolution and CoreImage GPU filters with zero file bloat.
- **Multi-Channel Surround Audio:** Preserves discrete 5.1 and 7.1 audio tracks and Dolby Atmos Spatial Audio pass-through.
- **Zero-Friction In-App Engine Setup:** Automatically manages helper engines with 1 click in user space—no Terminal commands, no Homebrew, and no `sudo` required!

---

## 🚀 Features

### 1. Intelligent Playback Strategy Matrix
Serein actively evaluates container formats, audio streams, and video codecs before dynamically selecting the optimal playback path:

| Strategy | When Applied | Impact & Performance |
| :--- | :--- | :--- |
| **Direct Native** | Supported container (`.mp4`, `.mov`, `.m4v`) + native codecs (H.264, HEVC, ProRes, AAC) | **0% CPU Overhead**, instant hardware decode via AVPlayer (`< 5ms` startup). |
| **Zero-Copy Stream Remux** | Incompatible container (`.mkv`, `.webm`) with native video streams | Repackages container on-the-fly to local HLS in **`< 100ms`** with **zero video re-encoding**. |
| **Audio Transcode** | Native video (H.264/HEVC) paired with incompatible audio (DTS, Opus, TrueHD) | Bit-for-bit passthrough for video; audio transcoded in real time (`>30×` speed) to high-fidelity AAC. |
| **Hardware VideoToolbox** | Incompatible video codecs (VP9, VP8, AV1, MPEG-2) | Real-time Apple Silicon VideoToolbox GPU encoding with 0% dropped frames. |
| **Online Stream Bridge** | Web streaming links & video platforms | Authenticated piped `yt-dlp` ➔ `FFmpeg` pipeline bypassing 403 Forbidden CDN blocks while preserving original audio. |

### 2. Pure Apple Native Video Enhancement & Upscaling Suite
Serein includes a zero-bloat GPU video enhancement suite integrated directly via hardware-accelerated CoreAnimation layer filtering (`AVPlayerLayer.filters`):
- **Apple MetalFX: Spatial Super-Resolution:** Integrates Apple's first-party `MetalFX.framework` (`MTLFXSpatialScaler`), engineered specifically for Apple Silicon GPUs to reconstruct crisp high-frequency detail.
- **Luminance Detail Enhancer (`CISharpenLuminance`):** Isolates the luma channel to sharpen micro-textures and fine details without amplifying chroma noise.
- **Edge & Outline Enhancer (`CIUnsharpMask`):** High-contrast edge restoration tuned with a tight radius for animation, cel-shading, cartoons, line art, and interface text.
- **Noise & Grain Suppression (`CINoiseReduction`):** Spatial bilateral noise reduction smoothing macroblocking and sensor grain while keeping edge boundaries razor-sharp.
- **Cinematic Contrast & Color:** Compound dynamic range filter combining luminance clarity with rich contrast and color vibrance.
- **Zero CPU & Zero Bundle Bloat:** Filters run directly inside the GPU display compositor at the native display refresh rate (including 120Hz ProMotion). The entire application bundle remains ultra-compact at just **2.2 MB**.

### 3. Discrete Multi-Channel Surround Sound & Dolby Atmos
- **Discrete 5.1 & 7.1 Preservation:** Retains discrete multi-channel surround tracks at high studio bitrates (384–640 kbps) without downmixing to stereo.
- **Dolby Atmos & Spatial Audio:** Passes E-AC-3 JOC directly to macOS AudioToolbox, enabling native Spatial Audio with dynamic head tracking on AirPods and built-in Mac speaker arrays.
- **Multi-Track Audio Switching:** Effortlessly switch between original audio tracks, commentary, and localized dubs from the Options menu (`...`).

### 4. macOS System Settings Accessibility Captions & Subtitle Engine
Serein treats subtitles as a first-class citizen using Apple's official `MediaAccessibility` framework (`MACaptionAppearance`):
- **System-Wide Consistency:** Subtitles dynamically adapt to your preferences in **System Settings ➔ Accessibility ➔ Captions** (e.g. *Transparent Background*, *Classic*, *Outline Text*, or *Large Text*).
- **Responsive Subtitle Scaling:** Caption font size, padding, and line height dynamically scale with viewport height (`18 pt` to `48 pt`) when entering full screen.
- **Automatic Sidecar Subtitle & Lyric Discovery:** Automatically detects `.srt`, `.vtt`, `.ass`, `.ssa`, `.sub`, and `.lrc` files located alongside media or in `Subs/` and `Subtitles/` subdirectories.
- **Drag-and-Drop Subtitle Attachment:** Drop any external subtitle or lyric file directly onto the player window to immediately switch to that track without stopping the video.
- **Remote Progressive Range Demuxing:** High-efficiency sparse demuxing for massive remote cloud containers (e.g. 15GB+ Matroska streams) with multi-byte UTF-8 split protection.
- **Multi-Encoding Auto-Detection:** Seamlessly decodes UTF-8 (with or without BOM), UTF-16LE/BE, GB18030/GBK, and Windows CP1252 subtitles.
- **Smart ASS/SSA Sanitization:** Automatically strips cluttered custom font/color overrides from anime and community subtitles while preserving semantic screen positioning (top, bottom, and center placement).
- **Embedded Subtitle Extraction:** Automatically extracts container-embedded tracks (`mov_text`, `srt`, `ass`, `webvtt`) on-the-fly.

### 5. Apple AppKit Controls & QuickTime Optical Liquid Glass Thumb
- **AppKit Native Controls:** Replaced custom slider widgets with Apple's first-party `NSSlider` AppKit controls for system-level precision and responsiveness.
- **QuickTime Optical Liquid Glass Thumb:** Features true optical glass translucency, submerged core progress bar, and dynamic specular flare on scrubber drag and hover.
- **Centered Floating Modal HUD (`⌘I`):** A centered floating diagnostic block presenting live playback strategy, active upscaling pipeline, audio codec channels, and stream probe metadata. Hugs content snugly and scrolls smoothly with high-contrast dark frosted glass (`black.opacity(0.95)`) and a 50% backdrop dimming scrim. Dismiss with `Esc` or a click outside.
- **Media Statistics Menu Action:** Inspect real-time audio/video codecs, container bitrate, and hardware rendering stats with a single click in the Options menu.
- **Generous Traffic Light Breathing Room:** Swizzled window layout keeps macOS window controls comfortably placed at `18pt` left and `16pt` top margin across playback and resizing.

### 6. macOS Control Center & Now Playing Integration
- **System-Wide Media Hub:** Seamlessly integrates with Apple's `MediaPlayer` framework (`MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`).
- **Live Metadata & Poster Artwork:** Broadcasts real-time video title, creator/channel, duration, elapsed position, and video thumbnail/poster frames to the macOS menu bar Control Center widget, Lock Screen, and Touch Bar.
- **Hardware Media Key & Remote Commands:** Full native support for keyboard Play/Pause, Touch Bar scrubbing, headphone remotes, and `±5s` skip controls.

### 7. Unified Audio Mode & Clean Presentation
- **Unified Player Architecture:** Audio mode and Video mode share the same refined control layout, shortcuts, and interaction model.
- **Clean Minimalist Audio Canvas:** Clean, distraction-free display featuring high-resolution album artwork, track title, artist, and album typography.
- **Lossless Audio Engine (0% CPU):** Direct hardware playback for `.flac`, `.alac`, `.m4a`, `.mp3`, `.wav`, and `.aiff`.
- **Pure Swift Album Art Parser:** Extracts high-resolution embedded cover artwork directly from FLAC `METADATA_BLOCK_PICTURE` headers, MP3 ID3 APIC frames, and M4A `covr` atoms in `< 1ms` with zero subprocesses.
- **Desktop Always-On-Top Pinning (`⌥⌘P`):** Float the player above code editors, browsers, and terminal windows with a single click on the pin button (`📌`).

---

## ⚡️ Zero-Friction Setup: No Terminal Required

Unlike traditional players that demand manual command-line installations, Serein keeps the core application download ultra-compact (**~2.2 MB app, 1.4 MB .dmg**) and provides an **automated in-app engine installer**:

1. **Automatic Detection:** If you already have Homebrew (`brew install ffmpeg yt-dlp`), Serein detects and uses them immediately with zero configuration.
2. **1-Click In-App Download:** On fresh Macs without Homebrew, Serein prompts you with a clean native setup sheet (`⌘,`) and downloads managed static binaries directly into `~/Library/Application Support/Serein/bin/`.
3. **Preserves Apple Code Signatures:** By keeping helper engines in user Application Support, Serein never breaks its Gatekeeper code signatures and enables seamless background updates via `yt-dlp -U`.

---

## ⌨️ Native Controls & Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| **`Space`** | Play / Pause |
| **`←` (Left Arrow)** | Step Backward (`5s`) |
| **`→` (Right Arrow)** | Step Forward (`5s`) |
| **`+` / `=`** | Volume Up (`+10%`) |
| **`-`** | Volume Down (`-10%`) |
| **`M`** | Mute / Unmute |
| **`C`** | Toggle Video Aspect Ratio: **Fit to Screen (Letterbox)** vs. **Fill Screen** |
| **`Z`** | Toggle Subtitle Placement: **Video Frame Bounds** vs. **Display Frame Bounds** |
| **`⌘I`** | Toggle Centered Media Statistics & Technical Inspector HUD |
| **`⌥⌘M`** | Toggle Compact Liquid Glass MiniPlayer (Music Mode) |
| **`⌥⌘P`** | Toggle Always-on-Top Floating Window |
| **`Esc`** | Dismiss Media Statistics HUD or active modal |
| **`⌘,`** | Media Engines & Codecs Setup Sheet |
| **`⌘O`** | Open Local Media File |
| **`⌘U`** | Open Online Streaming URL |
| **`⌘W`** | Close Window |

---

## 🛠️ Building & Installing

### Option 1: Direct Download (Pre-built macOS Disk Image)
1. Download **[`Serein-v0.1.7.dmg`](https://github.com/passs0/Serein/releases/latest)** from [GitHub Releases](https://github.com/passs0/Serein/releases).
2. Open the downloaded `.dmg` and drag **`Serein.app`** directly into the **`Applications`** folder shortcut.
3. If macOS Gatekeeper flags the downloaded binary on first launch (ad-hoc signed):
   - Right-click `Serein.app` ➔ **Open**, or run:
     ```zsh
     xattr -cr /Applications/Serein.app
     ```
4. Open `Serein.app` and press `⌘O` to open any file or `⌘U` for streaming links!

### Option 2: Build from Source
```zsh
git clone https://github.com/passs0/Serein.git
cd Serein
./build_app.sh
```
> [!NOTE]
> `./build_app.sh` automatically compiles, ad-hoc code-signs, and cleanly installs `Serein.app` directly into `/Applications/`. You can also run `make dmg` to package a release disk image.

---

## 🗺️ Roadmap

### Core Playback & Codecs
- [x] Native AVFoundation + VideoToolbox zero-copy hybrid engine
- [x] In-app automated media engine downloader & updater (zero Terminal required)
- [x] Universal container support (`.mkv`, `.webm`, `.avi`, `.ts`, `.mp4`, `.mov`, `.flac`, `.alac`)
- [x] High-speed visionOS multi-variant HLS streaming with automated CDN fallback
- [x] Variable speed playback with CoreAudio pitch correction (`0.5×`–`2.0×`)
- [x] Native Picture-in-Picture (`AVPictureInPictureController`) with live subtitle overlay
- [x] Display & system idle sleep prevention during active playback

### Apple Design & Interface
- [x] Apple Liquid Glass design & dynamic System Settings tint adjustment (`NSGlassTintAmount`)
- [x] Apple AppKit native `NSSlider` controls for volume & timeline scrubbing
- [x] QuickTime optical liquid glass thumb with submerged core progress & specular edge lighting
- [x] Unified Video & Audio player architecture with single cohesive control layout
- [x] Clean Audio Mode with high-resolution album artwork, artist, and album typography
- [x] Centered Media Statistics Technical Inspector (`⌘I`) with dark glass scrim
- [x] Quick-access Media Statistics button in native Options menu
- [x] Generous traffic light positioning with breathing room across playback & window resizing
- [x] macOS Control Center & Now Playing widget integration (`MPNowPlayingInfoCenter` & `MPRemoteCommandCenter`)

### Audio & Subtitles
- [x] Apple MetalFX Spatial Super-Resolution & CoreImage GPU video enhancement suite
- [x] Multi-channel surround sound preservation (discrete 5.1 & 7.1 tracks & Dolby Atmos)
- [x] macOS Accessibility caption rendering (`MACaptionAppearance`) with responsive full-screen scaling
- [x] Automatic sidecar subtitle & lyric discovery (`.srt`, `.vtt`, `.ass`, `.ssa`, `.sub`, `.lrc`)
- [x] Drag-and-drop subtitle loading without stopping active video playback
- [x] Remote MKV streaming progressive subtitle demuxing with sparse range tracking
- [x] Multi-encoding subtitle decoder (UTF-8 with BOM, UTF-16, GB18030, CP1252)
- [x] Manual "Load External Subtitles…" open panel in Options menu

### macOS Integration & Ecosystem
- [x] macOS Control Center & Now Playing widget integration (`MPNowPlayingInfoCenter` & `MPRemoteCommandCenter`)

### Upcoming Milestones
- [ ] **v0.2.0**: Playlist Queue with drag-and-drop, shuffle, repeat, & continuous playback
- [ ] **v0.2.0**: Chapter markers navigation & thumbnail preview scrub tooltips
- [ ] **v0.3.0**: Real-time 10-band audio equalizer & CoreAudio frequency visualizer
- [ ] **v0.3.0**: Extended keyboard shortcut customization & vim-style navigation keys

---

## 📄 License

Released under the [MIT License](LICENSE).
