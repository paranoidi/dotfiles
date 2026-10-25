function fnc --description '📋 Copy full path of a file or directory to clipboard'
    if test (count $argv) -ne 1
        echo "Usage: fnc FILE_OR_DIRECTORY" >&2
        return 1
    end

    if not test -e $argv[1]
        echo "🚫 fnc: '$argv[1]' does not exist" >&2
        return 1
    end

    set -l full_path (realpath -- $argv[1])
    printf '%s' "$full_path" | _clipboard_copy
    or return 1

    echo "🏆 Copied to clipboard: $full_path"
end
