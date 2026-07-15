#!/bin/bash
# =============================================================================
# NormalizeAudio.command
# Double-click this file in Finder to run the batch audio normalizer.
# This file must stay in the same folder as normalize_audio.py
# =============================================================================

# Get the folder this .command file lives in
# This means you can move both files together anywhere and it still works
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/normalize_audio.py"

# Add Homebrew to PATH (handles both Intel and Apple Silicon Macs)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Check the Python script exists next to this file
if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo "ERROR: normalize_audio.py not found in the same folder as this file."
    echo "Expected location: $PYTHON_SCRIPT"
    echo ""
    echo "Make sure NormalizeAudio.command and normalize_audio.py are in the same folder."
    read -p "Press Enter to close..."
    exit 1
fi

# Run it
python3 "$PYTHON_SCRIPT"

# Keep Terminal window open so you can read the results
echo ""
echo "Press Enter to close this window..."
read
