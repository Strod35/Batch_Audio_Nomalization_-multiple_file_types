#!/usr/bin/env python3
"""
================================================================================
  BATCH AUDIO NORMALIZER FOR XLIGHTS SEQUENCES
  normalize_audio.py
================================================================================
  Normalizes all audio files in a chosen folder to a consistent loudness level
  using ffmpeg's EBU R128 (two-pass loudnorm) algorithm.

  KEY BEHAVIOR:
    - Files are overwritten IN PLACE — filenames stay exactly the same
    - This keeps your xLights sequence-to-audio file bindings intact
    - Supports: .mp3, .wav, .flac, .ogg, .m4a, .aac, .wma

  PREREQUISITES:
    1. Python 3 (already on macOS)
    2. ffmpeg — install via Homebrew:  brew install ffmpeg
       Verify with:  ffmpeg -version

  USAGE:
    python3 normalize_audio.py
    (A folder picker dialog will open — select your xLights music folder)

  NORMALIZATION TARGET:
    Default: -16 LUFS — optimized for consumer FM transmitters
    (MaxDare, Whole House FM, and similar parking lot / drive-in units)
    True Peak: -1.0 dBTP

  FM TRANSMITTER CALIBRATION (do this BEFORE normalizing):
    1. Generate a 100 Hz sine tone (Audacity or any online generator)
    2. Play it into your transmitter's audio input at 70% volume
    3. Adjust transmitter input gain until modulation reads ~70-75%
    4. Lock that gain — don't touch it again
    After normalizing to -16 LUFS, every song will hit the transmitter
    at the same level automatically.

  NOTE ON FPP USERS:
    FPP v7.2+ has built-in MP3Gain normalization (Content Setup > File Manager
    > Audio tab > select files > Normalize). Use that if you only have MP3s.
    Use this script if you have WAV/FLAC/other formats, or need precise
    -16 LUFS targeting for FM transmitter setups.
================================================================================
"""

import os
import sys
import json
import subprocess
import tempfile
import shutil
import tkinter as tk
from tkinter import filedialog, messagebox


# ============================================================
# USER SETTINGS — adjust these if needed
# ============================================================

# Target integrated loudness in LUFS
# -16 = default, optimized for consumer FM transmitters (MaxDare, etc.)
# -14 = streaming standard (Spotify/YouTube) — slightly hot for FM
# -23 = licensed broadcast standard (EBU R128)
LUFS_TARGET      = -16.0

# True peak ceiling in dBTP — prevents clipping after encoding
TRUE_PEAK_TARGET = -1.0

# Loudness range target in LU (11 is EBU R128 standard)
LU_RANGE_TARGET  = 11.0

# Audio file extensions to process (add/remove as needed)
SUPPORTED_EXTENSIONS = {".mp3", ".wav", ".flac", ".ogg", ".m4a", ".aac", ".wma"}


# ============================================================
# HELPER: Check ffmpeg is installed
# ============================================================

def check_ffmpeg():
    if shutil.which("ffmpeg") is None:
        messagebox.showerror(
            "ffmpeg Not Found",
            "ffmpeg is not installed or not on your PATH.\n\n"
            "Install it with Homebrew:\n"
            "  brew install ffmpeg\n\n"
            "Then re-run this script."
        )
        sys.exit(1)


# ============================================================
# HELPER: Find all audio files in a directory
# ============================================================

def find_audio_files(folder_path):
    audio_files = []
    for filename in os.listdir(folder_path):
        ext = os.path.splitext(filename)[1].lower()
        if ext in SUPPORTED_EXTENSIONS:
            full_path = os.path.join(folder_path, filename)
            audio_files.append(full_path)
    return sorted(audio_files)


# ============================================================
# CORE: Two-pass EBU R128 normalization for a single file
# ============================================================

def normalize_file(input_path):
    # ----------------------------------------------------------
    # PASS 1: Measure loudness
    # ----------------------------------------------------------
    pass1_cmd = [
        "ffmpeg", "-hide_banner",
        "-i", input_path,
        "-af", (
            f"loudnorm="
            f"I={LUFS_TARGET}:"
            f"TP={TRUE_PEAK_TARGET}:"
            f"LRA={LU_RANGE_TARGET}:"
            f"print_format=json"
        ),
        "-f", "null", "-",
    ]

    try:
        result = subprocess.run(pass1_cmd, capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        return False, f"Pass 1 failed: {e.stderr[-500:]}"

    stderr_output = result.stderr
    json_start = stderr_output.rfind("{")
    json_end   = stderr_output.rfind("}") + 1

    if json_start == -1 or json_end == 0:
        return False, "Could not find loudnorm JSON in ffmpeg output."

    try:
        loudness_stats = json.loads(stderr_output[json_start:json_end])
    except json.JSONDecodeError as e:
        return False, f"Failed to parse loudnorm JSON: {e}"

    measured_I      = loudness_stats.get("input_i",      "-70")
    measured_TP     = loudness_stats.get("input_tp",     "-70")
    measured_LRA    = loudness_stats.get("input_lra",    "0")
    measured_thresh = loudness_stats.get("input_thresh", "-70")

    # ----------------------------------------------------------
    # PASS 2: Apply normalization → temp file
    # ----------------------------------------------------------
    file_ext = os.path.splitext(input_path)[1].lower()
    tmp_fd, tmp_path = tempfile.mkstemp(suffix=file_ext)
    os.close(tmp_fd)

    pass2_cmd = [
        "ffmpeg", "-hide_banner", "-y",
        "-i", input_path,
        "-af", (
            f"loudnorm="
            f"I={LUFS_TARGET}:"
            f"TP={TRUE_PEAK_TARGET}:"
            f"LRA={LU_RANGE_TARGET}:"
            f"measured_I={measured_I}:"
            f"measured_TP={measured_TP}:"
            f"measured_LRA={measured_LRA}:"
            f"measured_thresh={measured_thresh}:"
            f"linear=true:"
            f"print_format=summary"
        ),
        tmp_path,
    ]

    try:
        subprocess.run(pass2_cmd, capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        os.unlink(tmp_path)
        return False, f"Pass 2 failed: {e.stderr[-500:]}"

    try:
        shutil.move(tmp_path, input_path)
    except Exception as e:
        os.unlink(tmp_path)
        return False, f"File replace failed: {e}"

    return True, f"{float(measured_I):.1f} LUFS → {LUFS_TARGET} LUFS target | Peak: {measured_TP} dBTP"


# ============================================================
# MAIN
# ============================================================

def main():
    root = tk.Tk()
    root.withdraw()

    print("Opening folder picker...")
    folder = filedialog.askdirectory(title="Select your xLights Music Folder")

    if not folder:
        print("No folder selected — exiting.")
        sys.exit(0)

    print(f"\nSelected folder: {folder}\n")

    audio_files = find_audio_files(folder)

    if not audio_files:
        messagebox.showinfo(
            "No Files Found",
            f"No supported audio files found in:\n{folder}\n\n"
            f"Supported: {', '.join(sorted(SUPPORTED_EXTENSIONS))}"
        )
        sys.exit(0)

    total = len(audio_files)
    print(f"Found {total} audio file(s) to normalize.")
    print(f"Target: {LUFS_TARGET} LUFS / {TRUE_PEAK_TARGET} dBTP\n")
    print("=" * 60)

    succeeded = 0
    failed    = 0
    errors    = []

    for idx, filepath in enumerate(audio_files, start=1):
        filename = os.path.basename(filepath)
        print(f"[{idx:3d}/{total}] {filename} ...", end=" ", flush=True)

        ok, msg = normalize_file(filepath)

        if ok:
            print(f"✓  {msg}")
            succeeded += 1
        else:
            print(f"✗  ERROR: {msg}")
            failed += 1
            errors.append((filename, msg))

    print("\n" + "=" * 60)
    print(f"Done. {succeeded} succeeded, {failed} failed.\n")

    summary_msg = (
        f"Normalization complete!\n\n"
        f"  Target          : {LUFS_TARGET} LUFS / {TRUE_PEAK_TARGET} dBTP\n"
        f"  Files processed : {total}\n"
        f"  Succeeded       : {succeeded}\n"
        f"  Failed          : {failed}\n\n"
        f"All filenames unchanged — xLights sequences unaffected."
    )

    if errors:
        summary_msg += "\n\nFailed files:\n"
        for fname, err in errors:
            summary_msg += f"  • {fname}: {err[:80]}\n"
        messagebox.showwarning("Normalization Complete (with errors)", summary_msg)
    else:
        messagebox.showinfo("Normalization Complete", summary_msg)


if __name__ == "__main__":
    check_ffmpeg()
    main()
