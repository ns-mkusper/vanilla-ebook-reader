#!/usr/bin/env python3
import argparse
import json
import re
import sys
import wave
from pathlib import Path


def normalize_words(text: str) -> list[str]:
    return re.findall(r"[a-z0-9']+", text.lower())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("wav", type=Path)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--expected", required=True)
    parser.add_argument("--min-coverage", type=float, default=0.72)
    args = parser.parse_args()

    try:
        from vosk import KaldiRecognizer, Model
    except ImportError as err:
        raise SystemExit("vosk is required for speech-to-text validation") from err

    expected_words = normalize_words(args.expected)
    if not expected_words:
        raise SystemExit("expected text has no words")

    with wave.open(str(args.wav), "rb") as wav:
        if wav.getnchannels() != 1 or wav.getsampwidth() != 2:
            raise SystemExit("STT validation requires mono 16-bit PCM WAV")
        recognizer = KaldiRecognizer(Model(str(args.model)), wav.getframerate())
        recognizer.SetWords(True)
        while True:
            data = wav.readframes(4000)
            if len(data) == 0:
                break
            recognizer.AcceptWaveform(data)
        result = json.loads(recognizer.FinalResult())

    transcript = result.get("text", "")
    transcript_words = normalize_words(transcript)
    transcript_set = set(transcript_words)
    covered = [word for word in expected_words if word in transcript_set]
    coverage = len(covered) / len(expected_words)

    print(f"STT transcript: {transcript}")
    print(
        f"STT expected-word coverage: {coverage:.2%} "
        f"({len(covered)}/{len(expected_words)})"
    )
    if coverage < args.min_coverage:
        missing = [word for word in expected_words if word not in transcript_set]
        raise SystemExit(
            "speech transcript did not match expected text; "
            f"missing={missing[:20]}"
        )


if __name__ == "__main__":
    main()
