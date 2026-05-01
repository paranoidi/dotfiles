function gadd --description "🔀 git add files with fzf"
    if not git rev-parse --git-dir >/dev/null 2>&1
        echo "gadd: Not in a git repository." >&2
        return 1
    end

    set -l status_output (git -c color.status=always status --porcelain=v1)
    if test -z "$status_output"
        echo "gadd: Working tree clean." >&2
        return 0
    end

    # Preview: show diff for unstaged changes, staged diff for staged-only,
    # and full file content for untracked. Run via sh because fzf's default
    # shell on this system is fish.
    set -l preview_script '
        line=$1
        x=$(printf "%s" "$line" | cut -c1)
        y=$(printf "%s" "$line" | cut -c2)
        path=$(printf "%s" "$line" | cut -c4-)
        case "$path" in
            *" -> "*) path=${path##* -> } ;;
        esac
        path=${path#\"}; path=${path%\"}
        if [ "$x" = "?" ]; then
            echo "── Untracked: $path ──"
            if [ -d "$path" ]; then
                ls -la -- "$path"
            elif command -v bat >/dev/null 2>&1; then
                bat --color=always --style=numbers --paging=never -- "$path"
            else
                cat -- "$path"
            fi
        else
            if [ "$y" != " " ] && [ -n "$y" ]; then
                echo "── Unstaged diff: $path ──"
                git diff --color=always -- "$path"
            fi
            if [ "$x" != " " ] && [ -n "$x" ] && [ "$x" != "?" ]; then
                echo "── Staged diff: $path ──"
                git diff --color=always --cached -- "$path"
            fi
        fi
    '
    set -l preview_cmd "sh -c $(string escape -- $preview_script) _ {}"

    # Restore script: unstages staged changes and discards working-tree
    # modifications. For untracked files (??), removes them.
    set -l restore_script '
        for line in "$@"; do
            x=$(printf "%s" "$line" | cut -c1)
            y=$(printf "%s" "$line" | cut -c2)
            path=$(printf "%s" "$line" | cut -c4-)
            case "$path" in
                *" -> "*) path=${path##* -> } ;;
            esac
            path=${path#\"}; path=${path%\"}
            if [ "$x" = "?" ]; then
                rm -rf -- "$path"
            else
                if [ "$x" != " " ] && [ -n "$x" ]; then
                    git restore --staged -- "$path" >/dev/null 2>&1
                fi
                if [ "$y" != " " ] && [ -n "$y" ]; then
                    git restore -- "$path" >/dev/null 2>&1
                fi
            fi
        done
    '
    set -l restore_cmd "sh -c $(string escape -- $restore_script) _ {+}"
    set -l reload_cmd 'git -c color.status=always status --porcelain=v1'

    set -l selected (
        printf "%s\n" $status_output |
        fzf --ansi \
            --multi \
            --height=80% \
            --reverse \
            --border \
            --prompt="git add> " \
            --header="TAB: select  Ctrl-R: restore  Ctrl-P: toggle preview" \
            --preview=$preview_cmd \
            --preview-window=right:60%:wrap \
            --bind="ctrl-p:toggle-preview" \
            --bind="ctrl-r:execute-silent($restore_cmd)+reload($reload_cmd)" \
            --with-nth=2..
    )
    or return

    set -l paths
    for line in $selected
        set -l rest (string sub --start=4 -- $line)
        set -l x (string sub --length=1 -- $line)
        if test "$x" = R
            set rest (string split -- " -> " $rest)[-1]
        end
        # strip surrounding quotes
        set rest (string trim --chars='"' -- $rest)
        set -a paths $rest
    end

    if test (count $paths) -eq 0
        return 0
    end

    git add -- $paths
    and git status --short
end
