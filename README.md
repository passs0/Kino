<p align="center">
  <img src="assets/icon_mac.png" width="160" height="160" alt="Kino Icon" />
</p>

<h1 align="center">Kino</h1>

<p align="center">
  A lightweight macOS media player with QuickTime ergonomics and support for MKV, WebM, AV1, VP9, FLAC, and web streams.
</p>

<p align="center">
  <a href="https://github.com/passs0/Kino/releases/latest"><img src="https://img.shields.io/github/v/release/passs0/Kino?label=Latest%20Release&color=007AFF" alt="Latest Release" /></a>
  <img src="https://img.shields.io/badge/macOS-13.0%2B%20%7C%20Apple%20Silicon-black?logo=apple" alt="macOS 13.0+" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License" /></a>
</p>

<p align="center">
  <img src="assets/preview.png" width="640" alt="Kino" />
</p>

---

## What it does

- **Zero-overhead native path:** Plays `.mp4` and `.mov` directly with `AVPlayer` at ~0% CPU, and remuxes `.mkv`/`.webm` to local HLS in `< 100ms` without re-encoding video.
- **Hardware transcode & streams:** Uses Apple VideoToolbox for VP9/AV1 and bridges web URLs via `yt-dlp` + `ffmpeg` (auto-managed in user space with no Homebrew required).
- **MetalFX & CoreImage filters:** Real-time GPU spatial upscaling, sharpening, and noise reduction.
- **Subtitles & audio:** Built-in OpenSubtitles.com search (`⌥⌘S`) with `MovieHash` matching, delay controls (`G` / `H`), sidecar `.srt`/`.ass`/`.vtt` discovery, 5.1/7.1 surround, Dolby Atmos, and lossless `.flac`/`.alac` playback with cover art.

## How it compares

| | Kino | QuickTime Player | IINA | VLC | Infuse |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **App size** | ~3 MB | Built-in | ~140 MB | ~140 MB | ~80 MB |
| **Price / License** | Free (MIT) | Free | Free (GPL) | Free (GPL) | Freemium / Sub |
| **Native `AVPlayer` path** | Yes | Yes | No (`mpv`) | No (`libvlc`) | Custom Metal |
| **MKV / WebM / VP9 / AV1** | Yes (via `ffmpeg`) | No | Yes | Yes | Yes |
| **Web URLs (`yt-dlp`)** | Built-in | No | Built-in | Limited | No |
| **Apple MetalFX upscaling** | Yes | No | No | No | No |
| **OpenSubtitles search** | Built-in (`MovieHash`) | No | Plugin / built-in | Extension | Built-in |
| **SMB / Plex / Jellyfin library** | No | No | No | Yes | Yes |
| **Playlists & video editing** | No | Trim / Split | Playlists | Playlists | Library |
| **Intel Mac support** | No (Apple Silicon) | Yes | Yes | Yes | Yes |

**Where Kino falls short:**
- **No media library or network shares:** Unlike Infuse or VLC, Kino doesn't browse SMB/NFS shares, Plex, or Jellyfin libraries—it's a single-file/URL player.
- **No playlists or trim/export tools:** QuickTime handles quick trimming and screen recording; IINA and VLC support playlists and deeper `mpv`/shader scripting.
- **Depends on `ffmpeg`/`yt-dlp` for non-native formats:** `.mkv`, VP9, AV1, and web streams require Kino's user-space helper download on first use, and seeking on heavy software-decoded streams isn't as instant as `mpv` in IINA.
- **Apple Silicon & macOS 13+ only:** No Intel Mac, iOS, or tvOS builds.

## Install

Download **`Kino-v1.1.2.dmg`** from [Releases](https://github.com/passs0/Kino/releases/latest) and drag `Kino.app` to `/Applications`.

If Gatekeeper blocks the first launch:
```zsh
xattr -cr /Applications/Kino.app
```

Or build from source:
```zsh
git clone https://github.com/passs0/Kino.git && cd Kino
./build_app.sh
cp -R build/Kino.app /Applications/
```

## AI Scope

All code, UI/assets, and documentation in this project were generated with [Google Antigravity](https://antigravity.google). Human involvement was limited to direction, design feedback, and hands-on testing.

## License

[MIT](LICENSE)
