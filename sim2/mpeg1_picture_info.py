#!/usr/bin/env python3
"""Print GOP time codes and picture headers from an MPEG-1 video stream.

This is deliberately a lightweight elementary-stream parser: it scans MPEG
start codes and decodes only the fixed-size GOP and picture headers.  It also
works on MPEG-1 system/program streams because video start codes retain their
normal form inside them.

This whole tool is AI generated

"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Iterator


PICTURE_TYPES = {1: "I", 2: "P", 3: "B", 4: "D"}
ASPECT_RATIOS = {
    1: "1:1 (square)", 2: "0.6735", 3: "0.7031", 4: "0.7615",
    5: "0.8055", 6: "0.8437", 7: "0.8935", 8: "0.9157",
    9: "0.9815", 10: "1.0255", 11: "1.0695", 12: "1.0950",
    13: "1.1575", 14: "1.2015",
}
FRAME_RATES = {
    1: ("24000/1001", 24000 / 1001), 2: ("24", 24.0),
    3: ("25", 25.0), 4: ("30000/1001", 30000 / 1001),
    5: ("30", 30.0), 6: ("50", 50.0),
    7: ("60000/1001", 60000 / 1001), 8: ("60", 60.0),
}


def start_codes(data: bytes) -> Iterator[tuple[int, int]]:
    """Yield (byte offset, code) for every 00 00 01 xx start code."""
    offset = 0
    while True:
        offset = data.find(b"\x00\x00\x01", offset)
        if offset < 0 or offset + 3 >= len(data):
            return
        yield offset, data[offset + 3]
        offset += 3


def parse_gop(data: bytes, offset: int) -> dict[str, object] | None:
    """Decode the 28-bit group_of_pictures_header following a B8 code."""
    if offset + 8 > len(data):
        return None
    value = int.from_bytes(data[offset + 4 : offset + 8], "big")
    drop_frame = (value >> 31) & 1
    hours = (value >> 26) & 0x1F
    minutes = (value >> 20) & 0x3F
    seconds = (value >> 13) & 0x3F
    pictures = (value >> 7) & 0x3F
    return {
        "offset": offset,
        "timecode": f"{hours:02}:{minutes:02}:{seconds:02}:{pictures:02}",
        "drop_frame": bool(drop_frame),
        "closed_gop": bool((value >> 6) & 1),
        "broken_link": bool((value >> 5) & 1),
    }


def parse_sequence(data: bytes, offset: int) -> dict[str, object] | None:
    """Decode the fixed 64-bit portion of a sequence_header (B3)."""
    if offset + 12 > len(data):
        return None
    value = int.from_bytes(data[offset + 4 : offset + 12], "big")
    aspect_code = (value >> 36) & 0xF
    frame_rate_code = (value >> 32) & 0xF
    bit_rate_value = (value >> 14) & 0x3FFFF
    rate = FRAME_RATES.get(frame_rate_code)
    return {
        "offset": offset,
        "width": (value >> 52) & 0xFFF,
        "height": (value >> 40) & 0xFFF,
        "aspect_ratio_code": aspect_code,
        "aspect_ratio": ASPECT_RATIOS.get(aspect_code, "reserved"),
        "frame_rate_code": frame_rate_code,
        "frame_rate": None if rate is None else rate[1],
        "frame_rate_name": None if rate is None else rate[0],
        "bit_rate": None if bit_rate_value == 0x3FFFF else bit_rate_value * 400,
        "vbv_buffer_size": ((value >> 3) & 0x3FF) * 16_384,
        "constrained_parameters": bool((value >> 2) & 1),
    }


def parse_picture(data: bytes, offset: int, gop: dict[str, object] | None) -> dict[str, object] | None:
    """Decode temporal_reference and picture_coding_type after a 00 code."""
    if offset + 6 > len(data):
        return None
    value = int.from_bytes(data[offset + 4 : offset + 6], "big")
    type_number = (value >> 3) & 0x7
    return {
        "offset": offset,
        "gop_timecode": None if gop is None else gop["timecode"],
        "temporal_reference": (value >> 6) & 0x3FF,
        "picture_type": PICTURE_TYPES.get(type_number, f"reserved({type_number})"),
    }


def inspect(data: bytes) -> Iterator[dict[str, object]]:
    current_gop: dict[str, object] | None = None
    for offset, code in start_codes(data):
        if code == 0xB3:
            sequence = parse_sequence(data, offset)
            if sequence is not None:
                yield {"kind": "sequence", **sequence}
        elif code == 0xB8:
            current_gop = parse_gop(data, offset)
            if current_gop is not None:
                yield {"kind": "gop", **current_gop}
        elif code == 0x00:
            picture = parse_picture(data, offset, current_gop)
            if picture is not None:
                yield {"kind": "picture", **picture}


def main() -> int:
    parser = argparse.ArgumentParser(description="Show MPEG-1 GOP and picture header fields.")
    parser.add_argument("stream", type=Path, help="MPEG-1 elementary or system/program stream")
    parser.add_argument("--json", action="store_true", help="emit newline-delimited JSON records")
    args = parser.parse_args()

    try:
        data = args.stream.read_bytes()
    except OSError as exc:
        parser.error(f"cannot read {args.stream}: {exc}")

    for record in inspect(data):
        if args.json:
            print(json.dumps(record))
        elif record["kind"] == "sequence":
            bit_rate = "variable" if record["bit_rate"] is None else f"{record['bit_rate']} bit/s"
            frame_rate = record["frame_rate_name"] or "reserved"
            constrained = ", constrained" if record["constrained_parameters"] else ""
            print(
                f"SEQUENCE @ 0x{record['offset']:08x}  {record['width']}x{record['height']}  "
                f"aspect={record['aspect_ratio']} (code {record['aspect_ratio_code']})  "
                f"fps={frame_rate} (code {record['frame_rate_code']})  "
                f"bitrate={bit_rate}  vbv={record['vbv_buffer_size']} bits{constrained}"
            )
        elif record["kind"] == "gop":
            flags = []
            if record["drop_frame"]:
                flags.append("drop-frame")
            if record["closed_gop"]:
                flags.append("closed")
            if record["broken_link"]:
                flags.append("broken-link")
            suffix = f" ({', '.join(flags)})" if flags else ""
            print(f"GOP     @ 0x{record['offset']:08x}  {record['timecode']}{suffix}")
        else:
            gop = record["gop_timecode"] or "--:--:--:--"
            print(
                f"PICTURE @ 0x{record['offset']:08x}  GOP {gop}  "
                f"temporal_ref={record['temporal_reference']:4d}  "
                f"type={record['picture_type']}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
