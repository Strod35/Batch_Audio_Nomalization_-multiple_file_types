# Batch Audio Normalizer for xLights

Normalize all audio files in your xLights music folder to a consistent loudness level in one step — without opening every file individually in Audacity.

Files are overwritten **in place**, so every filename stays exactly the same. Your xLights sequence-to-audio bindings are never broken.

---

## Why This Exists

xLights show runners typically have dozens of audio files recorded at wildly different loudness levels. Without normalization, your show sounds inconsistent — some songs are too quiet, others blow out the speakers. If you are broadcasting over an FM transmitter for a drive-in / parking lot show, uneven levels also cause over-modulation and distortion on the receiver end.

The standard advice is to normalize in Audacity one file at a time. This tool does the entire folder in a single run.

**Tested on:** macOS (Apple Silicon & Intel) · Windows support included (community testing welcome)

---

## What's in This Package

| File | Purpose |
|---|---|
| `normalize_audio.py` | Main Python script — runs the normalization |
| `NormalizeAudio.command` | macOS double-click launcher (no Terminal knowledge needed) |

---

## Supported Audio Formats

`.mp3` · `.wav` · `.flac` · `.ogg` · `.m4a` · `.aac` · `.wma`

---

## Prerequisites

### macOS

**1. Install Homebrew** (if not already installed):
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After installing on Apple Silicon (M1/M2/M3), add Homebrew to your PATH:
```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

**2. Install ffmpeg:**
```bash
brew install ffmpeg
```

**3. Verify:**
```bash
ffmpeg -version
```

Python 3 is already included with macOS.

---

### Windows

**1. Install Python 3** from https://python.org/downloads  
   ✅ Check **"Add Python to PATH"** during installation.

**2. Install ffmpeg:**
- Download a build from https://ffmpeg.org/download.html (get a "full" or "essentials" build)
- Extract the zip
- Add the `bin` folder to your Windows PATH:  
  Settings → System → Advanced system settings → Environment Variables → Path → New

**3. Verify in Command Prompt:**
```
python --version
ffmpeg -version
```

---

## Installation

1. Download `normalize_audio.py` and `NormalizeAudio.command` (macOS) into the same folder.  
   A good location is inside your xLights show folder, e.g. `_MyShow/Normalize Audio script/`.

2. **macOS only** — make the launcher executable (one-time setup):  
   Open Terminal, type `chmod +x ` (with a space), then drag `NormalizeAudio.command` into the Terminal window and press Enter.

---

## Usage

### macOS — Double-click method (recommended)
Double-click `NormalizeAudio.command` in Finder.  
A folder picker dialog will open. Select your xLights music folder and click Open.  
The Terminal window shows per-file progress and stays open until you press Enter.

### macOS / Windows — Terminal / Command Prompt
```bash
python3 normalize_audio.py
```
or on Windows:
```
python normalize_audio.py
```

### What you'll see
```
Found 25 audio file(s) to normalize.
Target: -16.0 LUFS / -1.0 dBTP

============================================================
[  1/25] Carol Of The Bells.mp3 ...  ✓  -22.9 LUFS → -16.0 LUFS target | Peak: -3.69 dBTP
[  2/25] Wizards In Winter.mp3 ...   ✓  -12.6 LUFS → -16.0 LUFS target | Peak: -1.32 dBTP
...
============================================================
Done. 25 succeeded, 0 failed.
```

---

## Normalization Target

The default target is **-16 LUFS**, optimized for consumer FM transmitters used in parking lot and drive-in holiday light shows (MaxDare, Whole House FM, and similar 0.1W–0.5W FCC-certified units).

To change the target, open `normalize_audio.py` in any text editor and adjust this line near the top:

```python
LUFS_TARGET = -16.0   # change this value
```

| Target | Use Case |
|---|---|
| `-16 LUFS` | **Default.** Consumer FM transmitters (parking lot / drive-in shows) |
| `-14 LUFS` | Streaming platforms (Spotify, YouTube) |
| `-23 LUFS` | Licensed broadcast standard (EBU R128) |

---

## FM Transmitter Calibration

**Do this once before normalizing your audio for the season.**

This is the standard procedure for setting input gain on a consumer FM transmitter so it handles normalized audio correctly:

1. Generate a **100 Hz sine tone** using Audacity (Generate → Tone) or any online tone generator.
2. Play the tone into your transmitter's audio input at **70% volume** (not 100%).
3. Adjust the transmitter's input gain/level until the modulation meter reads approximately **70–75%**, or the signal sounds clean with no distortion on a radio receiver in a nearby car.
4. **Lock that gain setting** — do not touch it again.

**Why 70% and not 100%?**  
A steady sine tone is a "perfect" signal. Real music has transient peaks that spike above the average level. Setting the reference tone at 70% leaves ~30% of headroom so musical peaks don't over-modulate the transmitter, which causes distortion and FM splatter onto adjacent channels.

**Why -16 LUFS?**  
After calibrating to the 70% tone reference, audio normalized to -16 LUFS with a -1 dBTP true peak ceiling drives the transmitter correctly — loud enough for good reception in passing cars, quiet enough to avoid clipping the input stage. Every song in your show hits the transmitter at the same level, so you calibrate once and the whole show runs consistently all season.

---

## How It Works

This tool uses **ffmpeg's EBU R128 two-pass loudnorm algorithm**:

- **Pass 1:** ffmpeg analyzes each file and measures its actual integrated loudness (LUFS), true peak, and loudness range.
- **Pass 2:** ffmpeg applies precise linear gain correction based on those measurements and writes the corrected audio.
- The corrected file then **replaces the original** using the same filename.

Two-pass normalization is significantly more accurate than single-pass peak normalization (what Audacity's default Normalize effect uses). It targets perceived loudness rather than just peak amplitude, which is why all songs sound consistently matched even with very different musical content.

---

## Alternative: FPP Built-in Normalizer

If you are running **FPP v7.2 or newer** and all your audio files are **MP3 format**, Falcon Player has MP3Gain normalization built directly into its web interface:

1. Open your FPP Web Interface
2. Go to **Content Setup → File Manager → Audio tab**
3. Select the files you want to normalize
4. Click **Normalize**

**Use this script instead when:**
- You have `.wav`, `.flac`, or other non-MP3 formats
- You need precise -16 LUFS targeting for FM transmitter optimization (FPP's MP3Gain defaults to approximately -14 LUFS and is not adjustable)
- You want to normalize files before uploading to FPP

---

## Note on xLights Lua Scripting

The xLights Lua scripting environment (`Tools → Run Scripts`) does not currently support calling external programs (`io.popen` is disabled in the sandbox). A Lua version of this tool would require the xLights team to expose an external command API. If you would like to see this integrated directly into xLights, please request it on the xLights GitHub or community forums.

---

## Community Testing

- ✅ Tested on **macOS** (Apple Silicon, xLights 2025/2026 season audio)
- ⬜ **Windows** — community testing welcome. Please report results in Issues.

---

## Contributing

Pull requests welcome. If you test on Windows and it works, please open a PR updating this README with confirmed Windows instructions and any differences you found.

---

## License

MIT — free to use, modify, and share.
