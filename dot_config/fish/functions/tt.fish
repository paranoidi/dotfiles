function __tt_pick_free_name
    set -l flowers sakura ume ayame nanohana kiku fuji ran sumire tsubaki asagao

    if not command tmux has-session -t=main 2>/dev/null
        echo main
        return
    end

    for name in $flowers
        if not command tmux has-session -t="$name" 2>/dev/null
            echo $name
            return
        end
    end

    echo s(date +%s)
end

function __tt_new_session
    set -l name (__tt_pick_free_name)

    if set -q TMUX
        command tmux new-session -d -s "$name"
        command tmux switch-client -t "$name"
    else
        command tmux new-session -A -s "$name"
    end
end

function __tt_detach_session_clients
    set -l session $argv[1]
    set -l current_session
    set -l current_client

    if set -q TMUX
        set current_session (command tmux display-message -p "#{session_name}" 2>/dev/null)
        set current_client (command tmux display-message -p "#{client_id}" 2>/dev/null)
    end

    if test "$session" != "$current_session"
        command tmux detach-client -s "$session" 2>/dev/null
        return 0
    end

    command tmux list-clients -t "$session" -F "#{client_id}" 2>/dev/null | while read -l client
        if test -n "$client"; and test "$client" != "$current_client"
            command tmux detach-client -t "$client" 2>/dev/null
        end
    end
end

function tt --description 'Tmux session switcher with fzf preview'
    if test (count $argv) -gt 0; and test "$argv[1]" = --new
        __tt_new_session
        return $status
    end

    if not command tmux list-sessions >/dev/null 2>/dev/null
        echo "No tmux sessions found, starting new session" >&2
        sleep 1s

        set -l name (__tt_pick_free_name)
        command tmux new-session -A -s "$name"
        return $status
    end

    set -l new_marker "✨"
    set -l preview_command "fish -c 'set -l session (string split -m 1 : -- \$argv[1])[1]; if test \"\$session\" = \"$new_marker\"; echo \"Create a new tmux session\"; exit 0; end; echo \"━━━ \$session ━━━\"; command tmux list-windows -t \"\$session\" -F \"  #{window_index}: #{window_name}#{?window_active, ●,}\" 2>/dev/null; echo; echo \"━━━ Active pane content ━━━\"; command tmux capture-pane -t \"\$session\" -p -e 2>/dev/null | head -30' -- {}"

    set -l selection (
        begin
            command tmux list-sessions -F "#{session_name}: #{session_windows} windows (#{session_attached} attached)" 2>/dev/null
            printf '%s\n' "$new_marker: new session"
        end | fzf --height=60% \
            --reverse \
            --border \
            --header="Select tmux session  (Ctrl-N: new)" \
            --bind="ctrl-n:last+accept" \
            --preview="$preview_command" \
            --preview-window=right:50%:wrap
    )

    if test -z "$selection"
        return 0
    end

    set -l session (string split -m 1 : -- "$selection")[1]

    if test "$session" = "$new_marker"
        set session (__tt_pick_free_name)
        command tmux new-session -d -s "$session"
    end

    if set -q TMUX
        __tt_detach_session_clients "$session"
        command tmux switch-client -t "$session"
    else
        command tmux attach-session -d -t "$session"
    end
end
