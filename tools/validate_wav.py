#!/usr/bin/env python3
import struct
import sys
import wave
from pathlib import Path

MIN_SECONDS = 1.0


def main() -> None:
    path = Path(sys.argv[1])
    with wave.open(str(path), "rb") as wav:
        channels = wav.getnchannels()
        sample_width = wav.getsampwidth()
        frame_rate = wav.getframerate()
        frames = wav.getnframes()
        data = wav.readframes(frames)

    if channels != 1:
        raise SystemExit(f"expected mono WAV, got {channels} channels")
    if sample_width != 2:
        raise SystemExit(f"expected 16-bit WAV, got {sample_width * 8}-bit")
    if frame_rate < 8_000:
        raise SystemExit(f"expected speech-rate WAV, got {frame_rate}Hz")
    if frames < frame_rate * MIN_SECONDS:
        raise SystemExit(f"expected at least {MIN_SECONDS}s of speech, got {frames / frame_rate:.2f}s")

    samples = list(struct.unpack(f"<{len(data) // 2}h", data))
    peak = max(abs(sample) for sample in samples)
    if peak < 1_000:
        raise SystemExit(f"audio is too quiet or silent: peak={peak}")

    window = max(1, frame_rate // 5)
    voiced_windows = 0
    for start in range(0, len(samples), window):
        segment = samples[start : start + window]
        if segment and max(abs(sample) for sample in segment) >= 500:
            voiced_windows += 1
    if voiced_windows < 3:
        raise SystemExit("audio does not contain enough voiced speech windows")

    print(
        f"{path}: valid {channels}ch {sample_width * 8}-bit {frame_rate}Hz "
        f"{frames} samples, peak={peak}, voiced_windows={voiced_windows}"
    )


if __name__ == "__main__":
    main()
