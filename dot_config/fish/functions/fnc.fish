function fnc --description ' Copy full path of a file or directory to clipboard 📋'
    if test (count $argv) -ne 1
        echo "Usage: cpath FILE_OR_DIRECTORY" >&2
        return 1
    end

    if not test -e $argv[1]
        echo "cpath: '$argv[1]' does not exist" >&2
        return 1
    end

    set -l full_path (realpath -- $argv[1])
    printf '%s' "$full_path" | xclip -selection clipboard

    echo "Copied to clipboard: $full_path"
end
