#!/usr/bin/env python3
"""Fails, naming them, if any of <glyphs> is in none of <font files>.

    glyph-coverage.py <glyphs> <font file>...
"""
import sys

from fontTools.ttLib import TTFont


def main(glyphs, fonts):
    covered = set().union(*(TTFont(font).getBestCmap().keys() for font in fonts))
    missing = [glyph for glyph in glyphs if ord(glyph) not in covered]
    if missing:
        sys.exit(f"no font covers: {' '.join(missing)}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
