function _spinner --description 'Run a command with a gum spinner when available'
    argparse --name=_spinner 'fallback-prefix=' -- $argv
    or return

    set -l title $argv[1]
    set -e argv[1]

    if test -z "$title"; or test (count $argv) -eq 0
        echo "Usage: _spinner [--fallback-prefix VALUE] TITLE COMMAND [ARGUMENTS...]" >&2
        return 2
    end

    if command -q gum
        gum spin --spinner dot --show-error --title "$title" -- fish -c '$argv[1] $argv[2..-1]' -- $argv
    else
        if set -q _flag_fallback_prefix
            echo "$_flag_fallback_prefix $title"
        else
            echo "$title"
        end

        $argv
    end
end
