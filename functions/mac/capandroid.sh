capandroid() {
    emulate -L zsh
    setopt err_return pipe_fail

    local usage="Usage:
  capandroid [OUTPUT.png]

Captures a screenshot from the connected Android device.

If OUTPUT.png is omitted:
  - Uses a temporary file.
  - Copies the image to the macOS clipboard.
  - Deletes the temporary file.

If OUTPUT.png is provided:
  - Saves the screenshot to OUTPUT.png.
  - Copies the image to the macOS clipboard."

    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        print -r -- "$usage"
        return 0
    fi

    command -v adb >/dev/null 2>&1 || { print -u2 "Error: 'adb' is required but not installed."; return 1 }
    command -v osascript >/dev/null 2>&1 || { print -u2 "Error: 'osascript' is required but not installed."; return 1 }

    adb get-state >/dev/null 2>&1 || { print -u2 "Error: No Android device connected."; return 1 }

    local output tmpfile=""

    if [[ $# -eq 0 ]]; then
        tmpfile="$(mktemp -t android-screenshot).png"
        output="$tmpfile"
    else
        output="$1"
        mkdir -p "$(dirname "$output")"
    fi

    print "Capturing screenshot..."

    if ! adb exec-out screencap -p > "$output"; then
        print -u2 "Error: Screenshot capture failed."
        [[ -n "$tmpfile" ]] && rm -f "$tmpfile"
        return 1
    fi

    if [[ ! -s "$output" ]]; then
        print -u2 "Error: Screenshot capture failed."
        [[ -n "$tmpfile" ]] && rm -f "$tmpfile"
        return 1
    fi

    osascript <<EOF
set imgPath to POSIX file "$output"
set the clipboard to (read imgPath as «class PNGf»)
EOF

    if [[ -n "$tmpfile" ]]; then
        rm -f "$tmpfile"
        print "Screenshot copied to clipboard."
    else
        print "Saved to: $output"
        print "Copied to clipboard."
    fi
}
