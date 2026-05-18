#!/usr/bin/env python3
# Generates DraftCanvas/Resources/Credits.rtf from Resources/Licenses/*.txt
# Run from repo root: python3 Scripts/generate-credits.py
# Re-run whenever OSS_ENTRIES changes (new library added/removed).

import os

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LICENSES_DIR = os.path.join(ROOT_DIR, "DraftCanvas/Resources/Licenses")
OUTPUT_PATH = os.path.join(ROOT_DIR, "DraftCanvas/Resources/Credits.rtf")

OSS_ENTRIES = [
    {"id": "vtracer",      "name": "vtracer",      "version": "0.6.5",   "license_type": "MIT",               "url": "https://github.com/visioncortex/vtracer",    "note": None},
    {"id": "visioncortex", "name": "visioncortex",  "version": "0.8.10",  "license_type": "MIT OR Apache-2.0", "url": "https://github.com/visioncortex/visioncortex","note": None},
    {"id": "image",        "name": "image",         "version": "0.23.14", "license_type": "MIT",               "url": "https://github.com/image-rs/image",           "note": None},
    {"id": "oxipng",       "name": "oxipng",        "version": "9.1.5",   "license_type": "MIT",               "url": "https://github.com/shssoichiro/oxipng",       "note": None},
    {"id": "pngquant",     "name": "pngquant",      "version": "2.x",     "license_type": "GPL v3",            "url": "https://pngquant.org/",                       "note": "Used as a standalone binary via subprocess invocation — not linked to Draft Canvas."},
]

SEP = "- " * 25


def rtf_char(c: str) -> str:
    cp = ord(c)
    if cp <= 127:
        if c == "\\":
            return "\\\\"
        if c == "{":
            return "\\{"
        if c == "}":
            return "\\}"
        return c
    signed = cp if cp <= 32767 else cp - 65536
    return f"\\u{signed}?"


def rtf_text(text: str) -> str:
    return "".join(rtf_char(c) for c in text)


def rtf_lines(text: str) -> str:
    return "\\par\n".join(rtf_text(line) for line in text.split("\n")) + "\\par\n"


parts: list[str] = []
parts.append(r"{\rtf1\ansi\deff0")
parts.append(r"{\fonttbl{\f0\fswiss\fcharset0 Helvetica;}{\f1\fmodern\fcharset0 Menlo;}}")
parts.append(r"\f0\fs24")
parts.append(r"{\b\fs28 Open Source Licenses}\par\par")
parts.append(r"DraftCanvas incorporates the following open-source software.\par\par")

for e in OSS_ENTRIES:
    parts.append(rtf_text(SEP) + r"\par\par")
    parts.append(r"{\b " + rtf_text(f"{e['name']} {e['version']}") + r"}\par")
    parts.append(r"License: " + rtf_text(e["license_type"]) + r"\par")
    parts.append(rtf_text(e["url"]) + r"\par")
    if e["note"]:
        parts.append(rtf_text(e["note"]) + r"\par")
    parts.append(r"\par")

    txt_path = os.path.join(LICENSES_DIR, f"{e['id']}.txt")
    with open(txt_path, encoding="utf-8") as f:
        license_text = f.read()

    parts.append(r"{\f1\fs20 ")
    parts.append(rtf_lines(license_text))
    parts.append(r"}\par")

parts.append(r"}")

with open(OUTPUT_PATH, "w", encoding="ascii") as f:
    f.write("\n".join(parts))

print(f"Generated: {OUTPUT_PATH}")
