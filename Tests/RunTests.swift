import Foundation

@main
struct TestMain {
    static func main() async {
        print("========================================")
        print("🧪 Kino Architecture & Engine Verification")
        print("========================================")

        // 1. Tool Locator Check
        let locator = ToolLocator.shared
        for tool in ["ffprobe", "ffmpeg", "yt-dlp"] {
            let info = locator.info(for: tool)
            print("🔧 Tool [\(tool)]: available=\(info.isAvailable), path=\(info.path ?? "nil"), version=\(info.version ?? "nil")")
            assert(info.isAvailable, "Tool \(tool) should be available on this machine")
        }

        // 2. FFprobe Deep Inspection Test
        let testMP4 = URL(fileURLWithPath: "/tmp/kino_sample_native.mp4")
        let testMKV = URL(fileURLWithPath: "/tmp/kino_sample_remux.mkv")
        let testWebM = URL(fileURLWithPath: "/tmp/kino_sample_transcode.webm")

        do {
            print("\n--- Testing FFprobe on Native MP4 ---")
            let probeMP4 = try await FFprobeService.shared.probe(url: testMP4)
            print("Format: \(probeMP4.containerFormat), Duration: \(probeMP4.formattedDuration), Video: \(probeMP4.primaryVideo?.videoCodec?.description ?? "none"), Audio: \(probeMP4.primaryAudio?.audioCodec?.description ?? "none")")
            let strategyMP4 = CompatibilityMatrix.evaluate(source: .local(testMP4), probe: probeMP4, onlineInfo: nil)
            print("Strategy evaluated: [\(strategyMP4.badgeLabel)] -> \(strategyMP4.strategyTitle)")
            assert(strategyMP4.badgeLabel == "DIRECT NATIVE", "Expected DIRECT NATIVE for MP4")
            print("✅ Correctly selected Direct Native Playback for MP4!")

            print("\n--- Testing FFprobe on MKV (Remux Candidate) ---")
            let probeMKV = try await FFprobeService.shared.probe(url: testMKV)
            print("Format: \(probeMKV.containerFormat), Video: \(probeMKV.primaryVideo?.videoCodec?.description ?? "none"), Audio: \(probeMKV.primaryAudio?.audioCodec?.description ?? "none")")
            let strategyMKV = CompatibilityMatrix.evaluate(source: .local(testMKV), probe: probeMKV, onlineInfo: nil)
            print("Strategy evaluated: [\(strategyMKV.badgeLabel)] -> \(strategyMKV.strategyTitle)")
            assert(strategyMKV.badgeLabel == "STREAM COPY", "Expected STREAM COPY for MKV with native codecs")
            print("✅ Correctly selected Stream-Copy Remux for MKV with native codecs!")

            print("\n--- Testing FFprobe on WebM (Transcode Candidate) ---")
            let probeWebM = try await FFprobeService.shared.probe(url: testWebM)
            print("Format: \(probeWebM.containerFormat), Video: \(probeWebM.primaryVideo?.videoCodec?.description ?? "none"), Audio: \(probeWebM.primaryAudio?.audioCodec?.description ?? "none")")
            let strategyWebM = CompatibilityMatrix.evaluate(source: .local(testWebM), probe: probeWebM, onlineInfo: nil)
            print("Strategy evaluated: [\(strategyWebM.badgeLabel)] -> \(strategyWebM.strategyTitle)")
            assert(strategyWebM.badgeLabel == "FULL HW TRANSCODE", "Expected FULL HW TRANSCODE for WebM")
            print("✅ Correctly selected Hardware Transcode for WebM (VP9/Opus)!")

            print("\n--- Testing FFmpeg Remux Pipeline to Local Streaming Session ---")
            let pipeline = FFmpegPipeline()
            pipeline.onLogLine = { line in
                print("[FFMPEG LOG] \(line)")
            }
            let playbackURL = try await pipeline.startSession(inputURL: testMKV, mode: .remuxCopy)
            print("Playback URL generated: \(playbackURL.absoluteString)")

            // Verify session directory contains playlist and TS segments
            let sessionDir = pipeline.activeSessionDirectory
            print("Session directory: \(sessionDir?.path ?? "nil")")
            if let dir = sessionDir {
                let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
                print("Generated stream files in session: \(files)")
                assert(files.contains("playlist.m3u8"), "Session must contain playlist.m3u8")
                let hasTs = files.contains { $0.hasSuffix(".ts") }
                assert(hasTs, "Session must contain at least one .ts video chunk")
            }

            pipeline.stop()
            print("✅ FFmpeg remux pipeline verified successfully!")

            print("\n========================================")
            print("🎉 ALL 4 TEST SUITES PASSED SUCCESSFULLY!")
            print("========================================")
            exit(0)
        } catch {
            print("❌ Test failed: \(error)")
            exit(1)
        }
    }
}
