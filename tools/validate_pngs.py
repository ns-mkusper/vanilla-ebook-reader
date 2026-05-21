#!/usr/bin/env python3
import struct
import sys
import zlib
from pathlib import Path


def nonwhite_ratio(path: Path) -> float:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path} is not a PNG")
    pos = 8
    idat = b""
    width = height = color_type = None
    while pos < len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        chunk_type = data[pos + 4 : pos + 8]
        chunk = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if chunk_type == b"IHDR":
            width, height, _bit_depth, color_type, *_ = struct.unpack(
                ">IIBBBBB", chunk
            )
        elif chunk_type == b"IDAT":
            idat += chunk
        elif chunk_type == b"IEND":
            break

    bytes_per_pixel = {2: 3, 6: 4}[color_type]
    raw = zlib.decompress(idat)
    stride = width * bytes_per_pixel
    previous = [0] * stride
    index = 0
    nonwhite = 0

    for _ in range(height):
        filter_type = raw[index]
        index += 1
        scanline = list(raw[index : index + stride])
        index += stride
        reconstructed = [0] * stride
        for x, value in enumerate(scanline):
            left = reconstructed[x - bytes_per_pixel] if x >= bytes_per_pixel else 0
            up = previous[x]
            up_left = previous[x - bytes_per_pixel] if x >= bytes_per_pixel else 0
            if filter_type == 0:
                resolved = value
            elif filter_type == 1:
                resolved = (value + left) & 255
            elif filter_type == 2:
                resolved = (value + up) & 255
            elif filter_type == 3:
                resolved = (value + ((left + up) // 2)) & 255
            else:
                predictor = left + up - up_left
                left_distance = abs(predictor - left)
                up_distance = abs(predictor - up)
                up_left_distance = abs(predictor - up_left)
                paeth = (
                    left
                    if left_distance <= up_distance and left_distance <= up_left_distance
                    else up
                    if up_distance <= up_left_distance
                    else up_left
                )
                resolved = (value + paeth) & 255
            reconstructed[x] = resolved
        previous = reconstructed
        for j in range(0, stride, bytes_per_pixel):
            red, green, blue = reconstructed[j], reconstructed[j + 1], reconstructed[j + 2]
            if not (red > 245 and green > 245 and blue > 245):
                nonwhite += 1

    return nonwhite / (width * height)


def main() -> None:
    for arg in sys.argv[1:]:
        path = Path(arg)
        ratio = nonwhite_ratio(path)
        print(f"{path}: non-white ratio {ratio:.3f}")
        if ratio < 0.20:
            raise SystemExit(f"{path} looks blank/white")


if __name__ == "__main__":
    main()
