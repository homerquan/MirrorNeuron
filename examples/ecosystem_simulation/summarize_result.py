#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def decode_first_json(raw: str) -> dict:
    decoder = json.JSONDecoder()
    for index, char in enumerate(raw):
        if char != "{":
            continue
        try:
            payload, _ = decoder.raw_decode(raw[index:])
            return payload
        except json.JSONDecodeError:
            continue
    raise ValueError("could not find JSON payload in result file")


def main() -> None:
    result_path = Path(sys.argv[1])
    result = decode_first_json(result_path.read_text())
    output = result.get("result", {}).get("output") or {}

    print(json.dumps(
        {
            "job_id": result.get("job_id"),
            "status": result.get("status"),
            "simulation": output,
        },
        indent=2,
    ))


if __name__ == "__main__":
    main()
