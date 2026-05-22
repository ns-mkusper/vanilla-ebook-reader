#!/usr/bin/env python3
import struct
import sys
import wave
from pathlib import Path

SAMPLE_TEXT = (
    "EPUB import fixture This copyright-free EPUB validates import through the "
    "emulator UI. Just Read It should restore and read this document aloud."
)
SAMPLE_RATE = 16_000
WORD_SECONDS = 0.28
SILENCE_SECONDS = 0.05


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
    if frame_rate != SAMPLE_RATE:
        raise SystemExit(f"expected {SAMPLE_RATE}Hz WAV, got {frame_rate}Hz")

    samples = list(struct.unpack(f"<{len(data) // 2}h", data))
    word_count = len(SAMPLE_TEXT.split())
    expected_per_word = int(SAMPLE_RATE * WORD_SECONDS) + int(
        SAMPLE_RATE * SILENCE_SECONDS
    )
    expected_samples = word_count * expected_per_word
    if len(samples) != expected_samples:
        raise SystemExit(
            f"expected {expected_samples} samples for text fixture, got {len(samples)}"
        )

    peak = max(abs(sample) for sample in samples)
    if peak < 2_000:
        raise SystemExit(f"audio is too quiet or silent: peak={peak}")

    voiced_samples = int(SAMPLE_RATE * WORD_SECONDS)
    for word_index in range(word_count):
        start = word_index * expected_per_word
        segment = samples[start : start + voiced_samples]
        segment_peak = max(abs(sample) for sample in segment)
        if segment_peak < 1_000:
            raise SystemExit(f"word segment {word_index} has no audible signal")

    print(
        f"{path}: valid {channels}ch {sample_width * 8}-bit {frame_rate}Hz "
        f"{len(samples)} samples, peak={peak}"
    )


if __name__ == "__main__":
    main()
