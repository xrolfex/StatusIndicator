#!/usr/bin/env python3
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Upload an ESP32-WROOM image in short ROM-loader transactions."
    )
    parser.add_argument("--port", required=True)
    parser.add_argument("--firmware", required=True, type=Path)
    parser.add_argument("--baud", type=int, default=115200)
    return parser.parse_args()


def platformio_package(name: str) -> Path:
    core_dir = Path(os.environ.get("PLATFORMIO_CORE_DIR", Path.home() / ".platformio"))
    return core_dir / "packages" / name


def image_segments(firmware: Path) -> list[tuple[int, Path]]:
    build_dir = firmware.parent
    return [
        (0x1000, build_dir / "bootloader.bin"),
        (0x8000, build_dir / "partitions.bin"),
        (
            0xE000,
            platformio_package("framework-arduinoespressif32")
            / "tools/partitions/boot_app0.bin",
        ),
        (0x10000, firmware),
    ]


def upload_chunk(
    esptool: Path,
    port: str,
    baud: int,
    address: int,
    chunk: Path,
) -> None:
    command = [
        sys.executable,
        str(esptool),
        "--chip",
        "esp32",
        "--port",
        port,
        "--baud",
        str(baud),
        "--before",
        "default_reset",
        "--after",
        "hard_reset",
        "--no-stub",
        "write_flash",
        "--no-compress",
        "--flash_mode",
        "dio",
        "--flash_freq",
        "40m",
        "--flash_size",
        "4MB",
        hex(address),
        str(chunk),
    ]
    for attempt in range(3):
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode == 0:
            return
        if attempt == 2:
            sys.stdout.write(result.stdout)
            sys.stderr.write(result.stderr)
            raise RuntimeError(f"Failed to write flash sector at {hex(address)}")


def main() -> None:
    args = parse_args()
    esptool = platformio_package("tool-esptoolpy") / "esptool.py"
    segments = image_segments(args.firmware)
    required_files = [esptool, *(image for _, image in segments)]
    missing = [str(path) for path in required_files if not path.is_file()]
    if missing:
        raise FileNotFoundError(f"Missing upload file(s): {', '.join(missing)}")

    chunk_size = 4096
    total = sum(
        (image.stat().st_size + chunk_size - 1) // chunk_size
        for _, image in segments
    )
    completed = 0

    with tempfile.TemporaryDirectory(prefix="teamslight-wroom-upload-") as directory:
        temporary_directory = Path(directory)
        for base_address, image in segments:
            data = image.read_bytes()
            for offset in range(0, len(data), chunk_size):
                chunk = temporary_directory / "sector.bin"
                chunk.write_bytes(data[offset : offset + chunk_size])
                upload_chunk(
                    esptool,
                    args.port,
                    args.baud,
                    base_address + offset,
                    chunk,
                )
                completed += 1
                print(f"Flashed sector {completed}/{total}", flush=True)

    print(f"Uploaded {args.firmware.name} to {args.port}")


if __name__ == "__main__":
    main()
