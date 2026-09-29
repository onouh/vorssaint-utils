# Intel recorder codec policy

Vorssaint records and exports through VideoToolbox. On Apple Silicon the HEVC encoder is the right default: better quality per bit at screen-content bitrates. On Intel Macs with the integrated GPUs (the Iris and HD families, including the Iris Plus 655) HEVC encoding is not reliable, so the Intel slices of a universal build prefer H.264. This document records why, what breaks without it, and how the codebase keeps the choice from being lost in a future merge.

## What breaks without it

The Intel failure is `kVTVideoEncoderMalfunctionErr` (OSStatus `-12902`) from the HEVC encoder. It has two properties that make it dangerous:

- **It does not surface when the session is configured.** `AVAssetWriter.canApply(outputSettings:forMediaType:)` accepts the HEVC settings, and encoder creation succeeds. The failure happens later, when compressed frames are demanded.
- **It surfaces only at `append` time.** `videoInput.append(_:)` returns `false`, the writer enters `.failed`, and everything after that drops. A recording dies mid-write under CPU load; an export dies while rendering through a custom video compositor (the export-speed path always does).

Neither failure is catchable up front, which is why the fix is a codec preference rather than a validation check.

## The policy

- **Master recordings** (`RecorderWriter.preferredCaptureCodec`): H.264 on x86_64 slices, HEVC on Apple Silicon.
- **Exports and shares** (`RecorderExporter.preferredOutputCodec`): same split.
- **Fallback**: both writers keep a `canApply` fallback to H.264 for platforms whose encoders lack the preference. That fallback cannot foresee a `-12902`-style malfunction — it only catches a codec a platform cannot configure at all — so it is a safety net, not the fix.
- H.264 encodes with `AVVideoProfileLevelH264HighAutoLevel`; HEVC keeps upstream's encoder defaults. Universal builds carry the right choice in each slice, so the same app is correct on both architectures.

This is a fork delta over upstream: upstream selects HEVC unconditionally and is correct to, on Apple-Silicon-only hardware.

## How the test suite guards it

`RecorderCodecPreferenceTests` (run with the `recording` suite) pins the policy three independent ways:

1. **Source shape.** It reads `RecorderWriter.swift` and `RecorderExporter.swift` and asserts each still contains an `#if arch(x86_64)` conditional whose Intel branch selects `.h264` and whose Apple Silicon branch selects `.hevc`, with the `canApply` fallback intact. If a merge flattens the conditional or swaps a branch, the failure names the file and what moved.
2. **Compiled constants.** The test harness (`Tests/generate_sources.py`) extracts the two private codec closures verbatim into `RecorderCodecClosures.swift`, failing closed if the declarations move or change shape. The suite asserts the compiled constants equal this architecture's expected choice — which stays true when the x86_64 test binary runs under Rosetta on an Apple Silicon runner, the way fork CI exercises the Intel slices.
3. **Behavioral proof.** It writes a real 64×64 master file through `RecorderWriter` and decodes the saved track's `CMFormatDescription` media subtype, asserting the file itself carries the preferred codec. This exercises the same VideoToolbox path a recording takes, not just the decision.

## Automated checks

Run on a supported Mac:

```sh
./build.sh --test-suite=recording
./build.sh --test
```

Fork CI (`.github/workflows/ci.yml`) cross-compiles `x86_64-apple-macosx14.0` on an Apple Silicon runner and runs the x86_64 test binary under Rosetta, so the Intel slices are compiled and exercised on every push even though no CI runner has Intel graphics. The behavioral check confirms the chosen codec was encoded; only real Intel hardware can reproduce the original malfunction, so a regression in the *policy* is caught by the suite, and a regression in *Intel hardware behavior* is caught by recording on an Intel Mac after an update.
