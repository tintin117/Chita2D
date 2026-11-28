#!/usr/bin/env python3
"""Make an annotated contact sheet from a Chita directional animation."""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw


CELL_SIZE = 128
FRAME_COUNT = 15
ROWS = ("SE", "S", "SW", "W", "NW", "N", "NE", "E")
HEADER = 22


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sheet", type=Path, help="Chita's 1920×1024 animation PNG")
    parser.add_argument("output", type=Path, help="Output PNG")
    parser.add_argument(
        "--frame", type=int, action="append", choices=range(FRAME_COUNT),
        metavar="0–14", help="Frame number; repeat for multiple frames",
    )
    parser.add_argument("--grid", type=int, default=0, help="Native pixel grid spacing, or 0 to hide the grid")
    parser.add_argument("--scale", type=int, choices=range(1, 5), default=2, help="Integer preview zoom")
    args = parser.parse_args()
    if args.grid < 0:
        parser.error("--grid must be zero or positive")
    if args.output.suffix.lower() != ".png":
        parser.error("output must end in .png")
    if args.output.resolve() == args.sheet.resolve():
        parser.error("the preview must have a different path from the source sheet")

    frames = args.frame or [0, 7, 14]
    with Image.open(args.sheet) as source:
        expected = (CELL_SIZE * FRAME_COUNT, CELL_SIZE * len(ROWS))
        if source.size != expected:
            parser.error(f"expected {expected[0]}×{expected[1]} source, got {source.width}×{source.height}")
        sheet = source.convert("RGBA")

    cell = CELL_SIZE * args.scale
    row_height = cell + HEADER
    preview = Image.new("RGB", (cell * len(ROWS), row_height * len(frames)), "#1b222c")
    draw = ImageDraw.Draw(preview)
    for band, frame in enumerate(frames):
        y = band * row_height
        for facing, label in enumerate(ROWS):
            x = facing * cell
            source_x, source_y = frame * CELL_SIZE, facing * CELL_SIZE
            tile = sheet.crop((source_x, source_y, source_x + CELL_SIZE, source_y + CELL_SIZE))
            tile = tile.resize((cell, cell), Image.Resampling.NEAREST)
            preview.paste(tile, (x, y + HEADER), tile)
            draw.text((x + 4, y + 4), f"Row {facing} {label} · frame {frame}", fill="#f5e4b7")
            if args.grid:
                draw_grid(draw, x, y + HEADER, cell, args.scale, args.grid)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    preview.save(args.output)


def draw_grid(draw: ImageDraw.ImageDraw, x: int, y: int, cell: int, scale: int, step: int) -> None:
    for pos in range(step, CELL_SIZE, step):
        offset = pos * scale
        draw.line((x + offset, y, x + offset, y + cell - 1), fill="#536479")
        draw.line((x, y + offset, x + cell - 1, y + offset), fill="#536479")
        draw.text((x + offset + 1, y + 2), str(pos), fill="#e1e7ed")
        draw.text((x + 2, y + offset + 1), str(pos), fill="#e1e7ed")


if __name__ == "__main__":
    main()
