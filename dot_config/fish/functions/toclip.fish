function toclip --description '📋 Copy stdin or file to clipboard without ANSI'
    if not type -q ansi2txt
        echo "🚫 toclip: ansi2txt is not installed (package colorized-logs)" >&2
        return 1
    end

    if test (count $argv) -gt 0
        ansi2txt < $argv[1] | _clipboard_copy
    else
        ansi2txt | _clipboard_copy
    end
    or return 1
    toast -f -d 1500 Copied
end

function toclipr --description '📋 Copy stdin or files to clipboard as-is'
    if test (count $argv) -gt 0
        cat $argv | _clipboard_copy
    else
        _clipboard_copy
    end
    or return 1
    toast -f -d 1500 Copied
end
