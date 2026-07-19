function claude --wraps=$HOME/.local/bin/claude --description '📸 Snapshot home dir then launch Claude AI agent'
    _snapshot_home

    if test -f AGENTS.md; and test -f CLAUDE.md; and not test -L CLAUDE.md
        if cmp -s AGENTS.md CLAUDE.md
            rm CLAUDE.md
        else
            read -l -P "AGENTS.md and CLAUDE.md mismatch detected, launch anyway? [Y/n] " answer
            if string match -qi n -- $answer
                return 1
            end
        end
    end

    set -l made_link ""
    if test -e AGENTS.md; and not test -e CLAUDE.md; and not test -L CLAUDE.md
        ln -s AGENTS.md CLAUDE.md
        set made_link (pwd)/CLAUDE.md
    end

    if not set -q TMUX
        set -l escaped (string join ' ' (string escape -- $argv))
        set -l cleanup ""
        if test -n "$made_link"
            set cleanup "; test -L \"$made_link\"; and rm \"$made_link\""
        end
        _tmux_window "$HOME/.local/bin/claude --dangerously-skip-permissions $escaped$cleanup"
        return
    end

    $HOME/.local/bin/claude --dangerously-skip-permissions $argv
    if test -n "$made_link"; and test -L "$made_link"
        rm "$made_link"
    end
end
