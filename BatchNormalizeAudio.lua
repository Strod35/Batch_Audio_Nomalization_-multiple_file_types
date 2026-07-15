-- Batch normalize all audio files in a chosen folder to a consistent loudness level (ffmpeg EBU R128).
--
-- BatchNormalizeAudio.lua
--
-- Batch normalizes all audio files in a chosen folder to a consistent
-- loudness level using ffmpeg EBU R128 two-pass loudnorm.
--
-- Files are overwritten IN PLACE — filenames stay exactly the same.
-- This preserves all xLights sequence-to-audio file bindings.
--
-- SUPPORTS: .mp3  .wav  .flac  .ogg  .m4a  .aac  .wma
--
-- REQUIRES: ffmpeg installed and on your system PATH
--   macOS  → brew install ffmpeg
--   Windows → https://ffmpeg.org/download.html  (add to PATH)
--
-- USAGE: Run from xLights  →  Script > Run Script > BatchNormalizeAudio.lua
--
-- -------------------------------------------------------------------------
-- FM TRANSMITTER CALIBRATION (do this BEFORE normalizing your audio)
-- -------------------------------------------------------------------------
-- Before running this script, set your transmitter's input level correctly
-- using a 100 Hz reference tone. This is the standard procedure:
--
--   1. Generate a 100 Hz sine tone (Audacity, online generator, or any DAW).
--   2. Play the tone into your transmitter's audio input.
--   3. Set your playback volume to 70% (not 100%).
--   4. Adjust the transmitter's input gain/level until the modulation meter
--      reads approximately 70–75% (or the signal sounds clean with no
--      distortion on a radio receiver in a nearby car).
--   5. Lock that gain setting — do not touch it again.
--
-- WHY 70% and not 100%?
--   A steady sine tone is a "perfect" signal — real music has transient peaks
--   that spike well above the average level. Setting the tone at 70% leaves
--   ~30% of headroom so musical peaks don't over-modulate the transmitter,
--   which causes distortion and splatter onto adjacent FM channels.
--
-- WHY -16 LUFS?
--   After calibrating to the 70% tone reference, audio normalized to -16 LUFS
--   with a -1 dBTP true peak ceiling will drive the transmitter correctly —
--   loud enough for good reception in cars, quiet enough to avoid clipping
--   the input stage. All songs will hit the transmitter at the same level,
--   so you tune the gain once and the whole show runs consistently.
-- -------------------------------------------------------------------------


-- =========================================================================
-- SETTINGS — adjust these if desired
-- =========================================================================

local LUFS_TARGET       = -16.0   -- Target integrated loudness (LUFS)
                                   -- -16 = DEFAULT — optimized for consumer FM transmitters
                                   --        (MaxDare, Whole House FM, and similar 0.1W–0.5W
                                   --        FCC-certified parking lot / drive-in units).
                                   --        Matches consumer line-level input sensitivity and
                                   --        prevents over-modulation / distortion in cars.
                                   -- -14 = Streaming standard (Spotify / YouTube) — hotter,
                                   --        may over-drive some FM transmitter input stages.
                                   -- -23 = Licensed broadcast standard (EBU R128) — correct
                                   --        for stations with external processing hardware.

local TRUE_PEAK_TARGET  = -1.0    -- True peak ceiling (dBTP) — prevents clipping

local LU_RANGE_TARGET   = 11.0    -- Loudness range target (LU) — EBU R128 default

-- Audio file extensions to process (lowercase — comparison is forced to lower)
local AUDIO_EXTENSIONS = {
    [".mp3"]  = true,
    [".wav"]  = true,
    [".flac"] = true,
    [".ogg"]  = true,
    [".m4a"]  = true,
    [".aac"]  = true,
    [".wma"]  = true,
}


-- =========================================================================
-- OS DETECTION
-- =========================================================================

-- package.config's first character is the path separator:
--   '/'  on macOS / Linux
--   '\'  on Windows
local sep        = package.config:sub(1,1)
local is_windows = (sep == '\\')


-- =========================================================================
-- HELPER: Check ffmpeg is available before doing any work
-- =========================================================================

local function check_ffmpeg()
    -- 'ffmpeg -version' exits 0 if installed, errors if not found
    -- io.popen captures the output; we only care whether it ran at all
    local test = io.popen("ffmpeg -version 2>&1")
    if test == nil then
        ShowMessage("ERROR: Could not run ffmpeg.\n\n" ..
                    "Install ffmpeg and make sure it is on your PATH:\n" ..
                    "  macOS:   brew install ffmpeg\n" ..
                    "  Windows: https://ffmpeg.org/download.html")
        return false
    end
    local out = test:read("*all")
    test:close()

    -- If output doesn't contain 'ffmpeg version', it wasn't found
    if not out:find("ffmpeg version") then
        ShowMessage("ERROR: ffmpeg not found on PATH.\n\n" ..
                    "  macOS:   brew install ffmpeg\n" ..
                    "  Windows: https://ffmpeg.org/download.html")
        return false
    end
    return true
end


-- =========================================================================
-- HELPER: Get file extension in lowercase  (e.g. "Song.MP3" → ".mp3")
-- =========================================================================

local function get_extension(filename)
    -- Match everything after the last dot, including the dot itself
    return filename:match("(%.[^%.]+)$"):lower()
end


-- =========================================================================
-- HELPER: List all supported audio files in a folder
-- Returns a table of full file paths
-- =========================================================================

local function list_audio_files(folder)
    local files = {}

    if is_windows then
        -- Windows: use 'dir /b' to list filenames only (no subdirs)
        -- We quote the path to handle spaces in folder names
        local cmd = 'dir /b "' .. folder .. '" 2>nul'
        local handle = io.popen(cmd)
        if handle == nil then return files end

        for filename in handle:lines() do
            -- get_extension returns nil if no dot — guard with 'and'
            local ext = filename:find("%.") and get_extension(filename) or nil
            if ext and AUDIO_EXTENSIONS[ext] then
                -- Build full path using Windows separator
                table.insert(files, folder .. sep .. filename)
            end
        end
        handle:close()
    else
        -- macOS / Linux: use 'ls -1' for one filename per line
        -- Single-quote the path to handle spaces
        local safe_folder = folder:gsub("'", "'\\''")   -- escape single quotes
        local cmd = "ls -1 '" .. safe_folder .. "' 2>/dev/null"
        local handle = io.popen(cmd)
        if handle == nil then return files end

        for filename in handle:lines() do
            local ext = filename:find("%.") and get_extension(filename) or nil
            if ext and AUDIO_EXTENSIONS[ext] then
                table.insert(files, folder .. sep .. filename)
            end
        end
        handle:close()
    end

    -- Sort alphabetically so progress log is easy to follow
    table.sort(files)
    return files
end


-- =========================================================================
-- HELPER: Escape a file path for safe use in shell commands
-- Handles spaces and special characters
-- =========================================================================

local function shell_quote(path)
    if is_windows then
        -- Windows cmd.exe: wrap in double quotes
        return '"' .. path .. '"'
    else
        -- macOS/Linux: escape single quotes, then wrap in single quotes
        return "'" .. path:gsub("'", "'\\''") .. "'"
    end
end


-- =========================================================================
-- HELPER: Get a temp file path with the same extension as the input
-- We write the normalized audio here before replacing the original
-- =========================================================================

local function get_temp_path(original_path)
    -- Extract the file extension from the original (e.g. ".mp3")
    local ext = get_extension(original_path)

    if is_windows then
        -- Use Windows temp folder (%TEMP% or fallback to C:\Temp)
        local tmp = os.getenv("TEMP") or os.getenv("TMP") or "C:\\Temp"
        return tmp .. "\\xlights_norm_temp" .. ext
    else
        -- macOS/Linux: use /tmp
        return "/tmp/xlights_norm_temp" .. ext
    end
end


-- =========================================================================
-- CORE: Two-pass EBU R128 normalization for a single audio file
--
-- PASS 1: ffmpeg analyzes the file and prints measured loudness as JSON
--         (no audio is written — output is discarded with -f null)
--
-- PASS 2: Those measured values feed back in as 'measured_*' params so
--         ffmpeg applies precise linear gain correction → writes temp file
--
-- THEN:   Temp file atomically replaces the original (same filename)
--
-- Returns: success (bool), message (string)
-- =========================================================================

local function normalize_file(input_path)

    local tmp_path = get_temp_path(input_path)
    local q_input  = shell_quote(input_path)   -- quoted for shell safety
    local q_tmp    = shell_quote(tmp_path)

    -- ------------------------------------------------------------------
    -- PASS 1: Measure loudness — capture stderr which contains the JSON
    -- '2>&1' redirects stderr into stdout so io.popen can read it
    -- ------------------------------------------------------------------

    local loudnorm_filter = string.format(
        "loudnorm=I=%.1f:TP=%.1f:LRA=%.1f:print_format=json",
        LUFS_TARGET, TRUE_PEAK_TARGET, LU_RANGE_TARGET
    )

    local pass1_cmd = string.format(
        "ffmpeg -hide_banner -i %s -af %s -f null - 2>&1",
        q_input,
        shell_quote(loudnorm_filter)
    )

    local handle = io.popen(pass1_cmd)
    if handle == nil then
        return false, "Could not launch ffmpeg for Pass 1"
    end
    local pass1_output = handle:read("*all")
    handle:close()

    -- ------------------------------------------------------------------
    -- Parse the JSON block from Pass 1 stderr output
    -- ffmpeg prints the loudnorm stats as a JSON object — we pull out
    -- the four values we need using Lua string pattern matching
    -- ------------------------------------------------------------------

    -- input_i      = measured integrated loudness (LUFS)
    -- input_tp     = measured true peak (dBTP)
    -- input_lra    = measured loudness range (LU)
    -- input_thresh = measured threshold (LUFS) — used by loudnorm internally

    local measured_I      = pass1_output:match('"input_i"%s*:%s*"([^"]+)"')
    local measured_TP     = pass1_output:match('"input_tp"%s*:%s*"([^"]+)"')
    local measured_LRA    = pass1_output:match('"input_lra"%s*:%s*"([^"]+)"')
    local measured_thresh = pass1_output:match('"input_thresh"%s*:%s*"([^"]+)"')

    -- If any value is missing, Pass 1 failed (bad file, wrong format, etc.)
    if not measured_I or not measured_TP or not measured_LRA or not measured_thresh then
        return false, "Could not parse loudnorm JSON from Pass 1 output"
    end

    -- ------------------------------------------------------------------
    -- PASS 2: Apply precise normalization using the measured values
    -- 'linear=true' uses linear gain (most accurate mode)
    -- Output goes to temp file — original is untouched until we're sure
    -- ------------------------------------------------------------------

    local pass2_filter = string.format(
        "loudnorm=I=%.1f:TP=%.1f:LRA=%.1f:measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s:linear=true:print_format=summary",
        LUFS_TARGET, TRUE_PEAK_TARGET, LU_RANGE_TARGET,
        measured_I, measured_TP, measured_LRA, measured_thresh
    )

    local pass2_cmd = string.format(
        "ffmpeg -hide_banner -y -i %s -af %s %s 2>&1",
        q_input,
        shell_quote(pass2_filter),
        q_tmp
    )

    local handle2 = io.popen(pass2_cmd)
    if handle2 == nil then
        return false, "Could not launch ffmpeg for Pass 2"
    end
    local pass2_output = handle2:read("*all")
    handle2:close()

    -- Check that the temp file was actually created
    -- We try to open it for reading — if it fails, ffmpeg errored out
    local check = io.open(tmp_path, "rb")
    if check == nil then
        return false, "Pass 2 failed — temp file not created. ffmpeg output:\n" .. pass2_output:sub(-300)
    end
    check:close()

    -- ------------------------------------------------------------------
    -- Replace original file with normalized temp file
    -- os.rename is atomic on the same filesystem (no partial writes)
    -- On Windows, must delete the original first (rename won't overwrite)
    -- ------------------------------------------------------------------

    if is_windows then
        os.remove(input_path)   -- Windows requires explicit delete before rename
    end

    local ok, err = os.rename(tmp_path, input_path)
    if not ok then
        return false, "Failed to replace original file: " .. (err or "unknown error")
    end

    return true, string.format(
        "%.1f LUFS → %.1f LUFS target  |  Peak: %s dBTP",
        tonumber(measured_I) or 0, LUFS_TARGET, measured_TP
    )
end


-- =========================================================================
-- MAIN
-- =========================================================================

-- Step 1: Verify ffmpeg is available before prompting the user for anything
if not check_ffmpeg() then
    return
end

-- Step 2: Ask user for the normalization target
-- (override LUFS_TARGET with user's selection)
local lufs_choice = PromptSelection(
    {
        '-16 LUFS  (Default — consumer FM transmitters, drive-in / parking lot shows)',
        '-14 LUFS  (Streaming standard — Spotify / YouTube)',
        '-23 LUFS  (Licensed broadcast standard — EBU R128)',
        'Use script default  (' .. LUFS_TARGET .. ' LUFS)',
    },
    'Select normalization target loudness'
)

if lufs_choice == '' then
    Log("Cancelled.")
    return
end

-- Parse the LUFS number out of whichever option the user picked
local chosen_lufs = lufs_choice:match("(-?%d+)%s+LUFS")
if chosen_lufs then
    LUFS_TARGET = tonumber(chosen_lufs)
end
Log("Normalization target: " .. LUFS_TARGET .. " LUFS  |  True Peak: " .. TRUE_PEAK_TARGET .. " dBTP")

-- Step 3: Prompt for the music folder path
local music_folder = PromptString(
    'Full path to your xLights music / audio folder\n' ..
    '(files are overwritten in place — filenames unchanged)'
)

if music_folder == nil or music_folder == '' then
    Log("Cancelled — no folder entered.")
    return
end

-- Strip trailing separator if present (keeps path construction clean)
music_folder = music_folder:gsub("[/\\]+$", "")
Log("Music folder: " .. music_folder)

-- Step 4: Find all supported audio files
local audio_files = list_audio_files(music_folder)
local total = #audio_files

if total == 0 then
    ShowMessage(
        "No supported audio files found in:\n" .. music_folder .. "\n\n" ..
        "Supported extensions: .mp3  .wav  .flac  .ogg  .m4a  .aac  .wma"
    )
    return
end

Log("Found " .. total .. " audio file(s) to normalize.")
Log(string.rep("-", 60))

-- Step 5: Normalize each file and track results
local succeeded = 0
local failed    = 0
local errors    = {}
local start_time = os.time()

for i, filepath in ipairs(audio_files) do
    -- Extract just the filename for cleaner log output
    local filename = filepath:match("[^\\/]+$") or filepath

    Log(string.format("[%d/%d] %s", i, total, filename))

    local ok, msg = normalize_file(filepath)

    if ok then
        Log("  ✓  " .. msg)
        succeeded = succeeded + 1
    else
        Log("  ✗  ERROR: " .. msg)
        failed = failed + 1
        table.insert(errors, filename .. ": " .. msg)
    end
end

-- Step 6: Summary
local elapsed = os.time() - start_time
Log(string.rep("-", 60))
Log(string.format(
    "Done in %d seconds.  %d succeeded  |  %d failed",
    elapsed, succeeded, failed
))

local summary = string.format(
    "Batch normalization complete!\n\n" ..
    "  Target           : %d LUFS / %.1f dBTP\n" ..
    "  Files processed  : %d\n" ..
    "  Succeeded        : %d\n" ..
    "  Failed           : %d\n" ..
    "  Elapsed time     : %d seconds\n\n" ..
    "All filenames are unchanged — xLights sequence bindings intact.",
    LUFS_TARGET, TRUE_PEAK_TARGET, total, succeeded, failed, elapsed
)

if #errors > 0 then
    summary = summary .. "\n\nFailed files:"
    for _, e in ipairs(errors) do
        summary = summary .. "\n  • " .. e
    end
    ShowMessage(summary)
else
    ShowMessage(summary)
end
