capios() {
    emulate -L zsh
    setopt err_return pipe_fail

    local usage="Usage:
  capios [-d DEVICE] [OUTPUT.png]
  capios -l
  capios -h

Captures a screenshot from a connected iOS device.

Options:
  -d, --device DEVICE   Selects the device. DEVICE is a UDID, a CoreDevice
                        identifier, or a part of the device name. The name
                        match ignores letter case. The CAPIOS_DEVICE
                        variable supplies the default.
  -l, --list            Prints the devices that can give a screenshot.
  -h, --help            Prints this text.

If OUTPUT.png is omitted:
  - Uses a temporary file.
  - Copies the image to the macOS clipboard.
  - Deletes the temporary file.

If OUTPUT.png is provided:
  - Saves the screenshot to OUTPUT.png.
  - Copies the image to the macOS clipboard.

A device is usable when it is paired and its tunnel state is not
'unavailable'. If two or more devices are usable and you select none,
the function prints the list and stops."

    local device="${CAPIOS_DEVICE:-}"
    local list_only=0
    local output=""

    while (( $# > 0 )); do
        case "$1" in
            -h|--help)
                print -r -- "$usage"
                return 0
                ;;
            -l|--list)
                list_only=1
                shift
                ;;
            -d|--device)
                if [[ -z "${2:-}" ]]; then
                    print -u2 "Error: '$1' needs a device name, UDID or identifier."
                    return 1
                fi
                device="$2"
                shift 2
                ;;
            --device=*)
                device="${1#--device=}"
                shift
                ;;
            --)
                shift
                break
                ;;
            -*)
                print -u2 "Error: unknown option '$1'."
                print -u2 "$usage"
                return 1
                ;;
            *)
                break
                ;;
        esac
    done

    if (( $# > 1 )); then
        print -u2 "Error: give one output path only. Found $# arguments."
        return 1
    fi
    output="${1:-}"

    local tool
    for tool in xcrun osascript jq; do
        command -v "$tool" >/dev/null 2>&1 || {
            print -u2 "Error: '$tool' is required but not installed."
            return 1
        }
    done

    local json
    json="$(xcrun devicectl list devices --json-output /dev/stdout 2>/dev/null)" || {
        print -u2 "Error: 'xcrun devicectl list devices' failed."
        return 1
    }

    # One line per usable device: UDID, identifier, name.
    # 'unavailable' contains 'available', so compare the state, do not match it.
    local -a rows
    rows=("${(@f)$(
        print -r -- "$json" | jq -r '
            .result.devices[]
            | select(.connectionProperties.pairingState == "paired")
            | select(.connectionProperties.tunnelState != "unavailable")
            | [ .hardwareProperties.udid,
                .identifier,
                .deviceProperties.name ]
            | @tsv
        '
    )}")

    local -a usable
    local row
    for row in "${rows[@]}"; do
        [[ -n "$row" ]] && usable+=("$row")
    done

    if (( ${#usable} == 0 )); then
        print -u2 "Error: No connected iOS device found."
        print -u2 "A device must be paired, unlocked and trusted."
        return 1
    fi

    local -a fields
    local udid identifier name

    if (( list_only )); then
        print "Devices that can give a screenshot:"
        for row in "${usable[@]}"; do
            fields=("${(@s.	.)row}")
            printf '  %s  %s\n' "${fields[1]}" "${fields[3]}"
        done
        return 0
    fi

    local -a matched
    if [[ -n "$device" ]]; then
        for row in "${usable[@]}"; do
            fields=("${(@s.	.)row}")
            udid="${fields[1]}"
            identifier="${fields[2]}"
            name="${fields[3]}"
            if [[ "$udid" == "$device" || "$identifier" == "$device" \
                  || "${name:l}" == *"${device:l}"* ]]; then
                matched+=("$row")
            fi
        done
        if (( ${#matched} == 0 )); then
            print -u2 "Error: No usable device matches '$device'."
            print -u2 "Run 'capios -l' to see the usable devices."
            return 1
        fi
    else
        matched=("${usable[@]}")
    fi

    if (( ${#matched} > 1 )); then
        print -u2 "Error: ${#matched} devices match. Select one with -d."
        for row in "${matched[@]}"; do
            fields=("${(@s.	.)row}")
            print -u2 -r -- "  ${fields[1]}  ${fields[3]}"
        done
        return 1
    fi

    fields=("${(@s.	.)matched[1]}")
    udid="${fields[1]}"
    name="${fields[3]}"

    local tmpdir=""
    if [[ -z "$output" ]]; then
        tmpdir="$(mktemp -d -t ios-screenshot)"
        output="$tmpdir/screenshot.png"
    else
        mkdir -p "$(dirname -- "$output")"
    fi

    print -r -- "Capturing screenshot from: $name"

    if ! xcrun devicectl device capture screenshot \
        --device "$udid" \
        --destination "$output"; then
        [[ -n "$tmpdir" ]] && rm -rf "$tmpdir"
        return 1
    fi

    [[ -s "$output" ]] || {
        print -u2 "Error: Screenshot capture failed."
        [[ -n "$tmpdir" ]] && rm -rf "$tmpdir"
        return 1
    }

    osascript - "$output" <<'EOF'
on run argv
    set imgPath to POSIX file (item 1 of argv)
    set the clipboard to (read imgPath as «class PNGf»)
end run
EOF

    if [[ -n "$tmpdir" ]]; then
        rm -rf "$tmpdir"
        print "Screenshot copied to clipboard."
    else
        print -r -- "Saved to: $output"
        print "Copied to clipboard."
    fi
}
