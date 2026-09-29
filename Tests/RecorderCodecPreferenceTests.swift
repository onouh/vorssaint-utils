// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import CoreMedia

/// Pins the per-architecture codec preference that keeps recordings alive on
/// Intel: the integrated Iris and HD GPUs fail HEVC encode with
/// kVTVideoEncoderMalfunctionErr (-12902), and the failure only surfaces when
/// a frame is appended, so the canApply fallback cannot foresee it. Upstream
/// keeps HEVC on Apple Silicon; Intel slices of this fork prefer H.264.
///
/// Three layers, so a future merge cannot silently drop the delta:
/// 1. The source keeps the preference architecture-conditional, with H.264 in
///    the x86_64 branch, HEVC in the other, and a canApply fallback.
/// 2. The compiled constants (extracted by the test harness) match this
///    architecture, which also holds when the x86_64 test binary runs under
///    Rosetta on an Apple Silicon runner.
/// 3. A real master file written through RecorderWriter encodes and decodes
///    with the preferred codec, on the same VideoToolbox path a recording
///    takes.
enum RecorderCodecPreferenceTests {
    static func run(_ suite: TestSuite) {
        checkSourceShape(suite)
        checkCompiledPreference(suite)
        checkGeneratedMasterCodec(suite)
    }

    private static func checkSourceShape(_ suite: TestSuite) {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for (file, constant) in [("RecorderWriter.swift", "preferredCaptureCodec"),
                                 ("RecorderExporter.swift", "preferredOutputCodec")] {
            let path = root.appendingPathComponent("Sources/Vorssaint/Services/Recorder/\(file)")
            guard let data = FileManager.default.contents(atPath: path.path),
                  let source = String(data: data, encoding: .utf8) else {
                suite.expect(false, "the codec pin could not read \(file)")
                continue
            }
            guard let conditional = source.range(of: "#if arch(x86_64)") else {
                suite.expect(false, "\(file) keeps the \(constant) architecture-conditional")
                continue
            }
            guard let elseBranch = source.range(of: "#else",
                                                range: conditional.upperBound..<source.endIndex),
                  let endif = source.range(of: "#endif",
                                           range: elseBranch.upperBound..<source.endIndex) else {
                suite.expect(false, "\(file) keeps both architecture branches for \(constant)")
                continue
            }
            let intelBranch = source[conditional.upperBound..<elseBranch.lowerBound]
            let siliconBranch = source[elseBranch.upperBound..<endif.lowerBound]
            suite.expect(intelBranch.contains(".h264") && !intelBranch.contains(".hevc"),
                         "\(file) prefers H.264 on Intel slices, where HEVC malfunctions")
            suite.expect(siliconBranch.contains(".hevc") && !siliconBranch.contains(".h264"),
                         "\(file) keeps upstream's HEVC choice on Apple Silicon slices")
            suite.expect(source.contains("canApply"),
                         "\(file) keeps the canApply fallback for encoders without the preference")
        }
    }

    private static func checkCompiledPreference(_ suite: TestSuite) {
        let expected = expectedPreference()
        suite.expect(writerPreferredCaptureCodec == expected,
                     "the master writer's capture codec preference matches this architecture")
        suite.expect(exporterPreferredOutputCodec == expected,
                     "the exporter's output codec preference matches this architecture")
    }

    /// Intel slices need H.264 because the integrated GPUs cannot sustain the
    /// HEVC encode; Apple Silicon keeps upstream's HEVC choice.
    private static func expectedPreference() -> AVVideoCodecType {
        #if arch(x86_64)
        return .h264
        #else
        return .hevc
        #endif
    }

    private static func checkGeneratedMasterCodec(_ suite: TestSuite) {
        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            do { try await encodeMasterAndVerifyCodec(suite) }
            catch { suite.expect(false, "recorder codec fixture failed: \(error)") }
            finished.signal()
        }
        suite.expect(finished.wait(timeout: .now() + 30) == .success,
                     "the master-encode codec check finishes within its bounded fixture deadline")
    }

    /// Writes the smallest master file the writer produces and decodes the
    /// saved track, asserting the codec the file actually carries.
    private static func encodeMasterAndVerifyCodec(_ suite: TestSuite) async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-codec-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = RecorderWriter(url: url, pixelSize: CGSize(width: 64, height: 64), frameRate: 30,
            capturesSystemAudio: false, capturesMicrophone: false, pauseClock: RecorderPauseClock())!
        precondition(writer.start())
        let origin = CMTime(value: 100, timescale: 1)
        writer.beginSession(at: origin)
        for index in [CMTimeValue(0), CMTimeValue(1)] {
            try await feed(video(at: origin + CMTime(value: index, timescale: 30)), kind: .video, to: writer)
        }
        let finished = await writer.finish(at: origin + CMTime(value: 2, timescale: 30))
        suite.expect(finished, "the minimal master file finishes with the architecture codec")
        guard finished else { return }
        let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
        suite.expect(tracks.count == 1, "the master file has one video track")
        guard let track = tracks.first else { return }
        let descriptions = try await track.load(.formatDescriptions)
        let codec = descriptions.first.map { CMFormatDescriptionGetMediaSubType($0) }
        let expectedCodec = writerPreferredCaptureCodec == .h264
            ? kCMVideoCodecType_H264
            : kCMVideoCodecType_HEVC
        suite.expect(codec == expectedCodec,
                     "the master file encodes with the architecture-preferred codec")
    }

    private static func feed(_ sample: CMSampleBuffer,
                             kind: RecorderCaptureEngine.Kind,
                             to writer: RecorderWriter) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        var attempts = 0
        while attempts < 5_000 && ProcessInfo.processInfo.systemUptime < deadline {
            switch writer.append(sample, kind: kind) {
            case .appended:
                return
            case .dropped:
                throw FixtureError.dropped(kind)
            case .notReady:
                attempts += 1
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        throw FixtureError.timedOut(kind)
    }

    private enum FixtureError: Error, CustomStringConvertible {
        case dropped(RecorderCaptureEngine.Kind)
        case timedOut(RecorderCaptureEngine.Kind)

        var description: String {
            switch self {
            case .dropped(let kind): "writer dropped required \(kind) fixture sample"
            case .timedOut(let kind): "writer stayed backpressured for required \(kind) fixture sample"
            }
        }
    }

    private static func video(at time: CMTime) -> CMSampleBuffer {
        var pixels: CVPixelBuffer?
        precondition(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
            nil, &pixels) == kCVReturnSuccess)
        CVPixelBufferLockBaseAddress(pixels!, [])
        memset(CVPixelBufferGetBaseAddress(pixels!), 0, CVPixelBufferGetDataSize(pixels!))
        CVPixelBufferUnlockBaseAddress(pixels!, [])
        var format: CMVideoFormatDescription?
        precondition(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: pixels!, formatDescriptionOut: &format) == noErr)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        precondition(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixels!,
            formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &sample) == noErr)
        return sample!
    }
}
