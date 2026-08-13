#!/usr/bin/env bash
# tmux-window-status cmd title path pane_id
# Outputs: "<icon> <info>" for one window status entry.
# Arguments passed from .tmux.conf:
#   $1  pane_current_command
#   $2  pane_title
#   $3  pane_current_path
#   $4  pane_id (for agent state capture; optional)
#   $5  1 if this is the current window (clears the "done" flag), else 0/empty
# Self-check: windows-status.sh --test

cmd="$1"
title="$2"
path="$3"
pane_id="$4"
is_current="$5"

normalize_cmd() {
    case "$1" in batcat) printf 'bat' ;; vim|nvim) printf 'vi' ;; git-remote-*|git-*) printf 'git' ;; *) printf '%s' "$1" ;; esac
}

command_icon() {
    local cmd="$1"
    case "$cmd" in
        fish)                   printf '🐟' ;;
        bash)                   printf '😼' ;;
        python3|python|uv|pip)  printf '🐍' ;;
        go|gofmt)               printf '🐹' ;;
        claude)                 printf '🧠' ;;
        cursor-agent)           printf '🚀' ;;
        hermes)                 printf '🤖' ;;
        ruby)                   printf '💎' ;;
        perl)                   printf '🐪' ;;
        git)                    printf '🔀' ;;
        task)                   printf '📝' ;;
        find|ag|rg)             printf '🔍' ;;
        sleep)                  printf '🕓' ;;
        docker)                 printf '📦' ;;
        sudo)                   printf '💥' ;;
        cp|rsync|dd)            printf '💾' ;;
        ssh|scp)                printf '📡' ;;
        curl|wget|gh)           printf '🌐' ;;
        eza|mc|pc)              printf '🗂️' ;;
        vi|nvim)                printf '✏️' ;;
        hx)                     printf '🧬' ;;
        rm)                     printf '💀' ;;
        du|htop)                printf '📊' ;;
        pi|llm|aichat|copilot)  printf '🧠' ;;
        bat|less)               printf '📃' ;;
        apt)                    printf '🔧' ;;
        man)                    printf '📖' ;;
        "./pc")                 printf '👨‍💻' ;;
        *)                      printf '%s' "$1" ;;
    esac
}

# Agent state from (title, bottom-of-screen text). Rules ported from
# herdr's src/detect/manifests/{claude,hermes,github-copilot,pi}.toml.
# Prints: working | blocked | idle
agent_state() {
    local cmd="$1" title="$2" text="${3,,}"    # lowercase text, herdr matches case-insensitively
    case "$cmd" in
        claude)
            # herdr priority: spinner title (1100) > screen blockers (850-980) > idle
            # Spinner glyph: braille (⠀-⣿, old CLI versions) or circleHalves (◐◑◒◓, current)
            if [[ "$title" =~ ^[⠀-⣿◐◑◒◓]\  ]]; then
                printf 'working'
            elif [[ "$text" == *'do you want to proceed?'* ]] ||
                 { [[ "$text" == *'esc to cancel'* ]] && [[ "$text" == *'enter to select'* ]]; }; then
                printf 'blocked'
            else
                printf 'idle'
            fi ;;
        hermes)
            # herdr priority: osc title blocked (1100) > osc title working (1050) >
            # interrupt hint (950) > prompt blockers (900) > classic cancel (500) > osc title idle (100)
            local ask_re=$'(^|\n)[[:space:]]*ask[[:space:]]+[^[:space:]]'
            if [[ "$title" =~ ^⚠[^[:space:]]?(\ |$) ]]; then
                printf 'blocked'
            elif [[ "$title" =~ ^⏳[^[:space:]]?(\ |$) ]]; then
                printf 'working'
            elif [[ "$text" == *'msg=interrupt'* || "$text" == *'ctrl+c to interrupt'* ]]; then
                printf 'working'
            elif { [[ "$text" == *'dangerous'* || "$text" == *'approval'* ||
                      ( "$text" == *'allow once'* && "$text" == *'deny'* ) ]] &&
                   [[ "$text" == *'enter confirm'* || "$text" == *'enter to confirm'* ||
                      "$text" == *'↑/↓ to select'* || "$text" == *'show full command'* ]]; } ||
                 { [[ "$text" == *'hermes needs your'* || "$text" =~ $ask_re || "$text" == *'type your answer'* ]] &&
                   [[ "$text" == *'enter confirm'* || "$text" == *'enter to confirm'* || "$text" == *'enter send'* ||
                      "$text" == *'press enter'* || "$text" == *'↑/↓ select'* || "$text" == *'↑/↓ to select'* ||
                      "$text" == *'other (type'* ]]; } ||
                 [[ "$text" == *'sudo password'* || "$text" == *'skill setup'* ||
                    ( "$text" == *'🔑'* && "$text" == *'for '* ) ]] ||
                 { [[ ( "$text" == *'approve once'* && "$text" == *'cancel'* ) ||
                      ( "$text" == *'start a new session'* && "$text" == *'keep going'* ) ]] &&
                   [[ "$text" == *'enter to confirm'* || "$text" == *'enter confirm'* ||
                      "$text" == *'type 1/2/3'* || "$text" == *'y/n quick'* ]]; }; then
                printf 'blocked'
            elif [[ "$text" == *'ctrl+c cancel'* ]]; then
                printf 'working'
            else
                printf 'idle'
            fi ;;
        copilot)
            if [[ "$text" == *'esc to cancel'* || "$text" == *'esc cancel'* ]]; then
                if [[ "$text" == *'enter to select'* || "$text" == *'enter to confirm'* ||
                      "$text" == *'enter to submit'* || "$text" == *'enter accept'* ]]; then
                    printf 'blocked'
                else
                    printf 'working'
                fi
            elif [[ "$text" == *'esc interrupt'* ]]; then
                printf 'working'
            else
                printf 'idle'
            fi ;;
        pi)
            # ponytail: herdr's pi relies on socket hooks; screen manifest only has this
            if [[ "$text" == *'working...'* ]]; then
                printf 'working'
            else
                printf 'idle'
            fi ;;
        cursor-agent)
            # herdr priority: approval prompts (300-320) > working hints (90-100) > idle
            if [[ "$text" == *'write to this file?'* || "$text" == *'run this command?'* ||
                  "$text" == *'waiting for approval'* || "$text" == *'(y) (enter)'* ||
                  "$text" == *'skip (esc or n)'* || "$text" == *'keep (n)'* ]]; then
                printf 'blocked'
            elif [[ "$text" == *'ctrl+c to stop'* ]] ||
                 [[ "$text" =~ (⬡|⬢|[⠀-⣿])\ [a-z]+ing ]]; then
                printf 'working'
            else
                printf 'idle'
            fi ;;
    esac
}

# Desktop/tmux toast via fish; tmux-only fallback when fish is unavailable.
agent_toast() {
    local icon="$1"; shift
    local msg="$*"
    if command -v fish >/dev/null 2>&1; then
        export TOAST_ICON="$icon" TOAST_MSG="$msg"
        fish -c '
            set -l flags
            set -q TOAST_FORCE; and set -a flags -f
            set -q TOAST_DURATION; and set -a flags -d $TOAST_DURATION
            toast -i "$TOAST_ICON" $flags -- "$TOAST_MSG"
        ' 2>/dev/null &
        unset TOAST_FORCE TOAST_DURATION
    elif command -v tmux >/dev/null 2>&1; then
        tmux display-message " $icon $msg" 2>/dev/null &
    fi
}

if [[ "$1" == --test ]]; then
    t() { local want="$1"; shift; local got; got="$(agent_state "$@")"
          [[ "$got" == "$want" ]] || { echo "FAIL: agent_state $* -> '$got', want '$want'"; exit 1; }; }
    t working claude '⠐ fix parser' ''
    t working claude '◐ fix parser' ''
    t idle    claude '✳ fix parser' ''
    t blocked claude '✳ fix parser' $'Bash command\nDo you want to proceed?\n ❯ 1. Yes'
    t blocked claude '✳ fix parser' $'Enter to select · Esc to cancel'
    t idle    claude '✳ fix parser' $'❯ '
    t blocked hermes '⚠ auth error' ''
    t working hermes '⏳ thinking' ''
    t idle    hermes '✓ done' ''
    t blocked hermes '' $'Dangerous command\nAllow once   Deny\nEnter confirm'
    t blocked hermes '' $'Hermes needs your input\nPress enter'
    t blocked hermes '' $'ask what filename?\nEnter send'
    t blocked hermes '' 'sudo password:'
    t blocked hermes '' $'Approve once   Cancel\nEnter to confirm'
    t working hermes '' 'ctrl+c to interrupt'
    t working hermes '' 'esc … ctrl+c cancel'
    t idle    hermes '' 'hermes> '
    t blocked copilot '' 'Enter to select · Esc to cancel'
    t working copilot '' 'Esc to cancel'
    t idle    copilot '' '> '
    t working pi '' 'Working...'
    t idle    pi '' 'pi> '
    t blocked cursor-agent '' 'Run this command? Run (once) (y)  Skip (esc or n)'
    t working cursor-agent '' 'Ctrl+C to stop'
    t working cursor-agent '' '⬢ Generating response'
    t idle    cursor-agent '' '> '
    echo OK
    exit 0
fi

command_title_mode() {
    case "$1" in
        ssh|scp)                printf 'remote' ;;
        vi|bat|less|man)        printf 'short' ;;
    esac
}

# Note: value is shortened by default fish_title to 10 characters
host_label() {
    case "$1" in
        hime)                   printf '🎬' ;;
        raspberryp)             printf '🍇' ;;
        mamoru)                 printf '🔦' ;;
        prox)                   printf '🛠️' ;;
        orochi)                 printf '🚗' ;;
        *)                      printf '%s' "${1:0:4}" ;;
    esac
}

short_title() {
    local raw_title="$1"
    local normalized_cmd="$2"
    local original_title_cmd="$3"
    local short_info="$raw_title"

    short_info="${short_info#$normalized_cmd }"
    short_info="${short_info#$original_title_cmd }"
    short_info="${short_info% - ${original_title_cmd^^}}"  # strip trailing " - CMD" suffix (e.g. nvim → " - NVIM", vim → " - VIM")
    short_info="${short_info% [~\/]*}"       # strip trailing path-like word
    printf '%s' "$short_info"
}

# normalize aliases so icon + title-strip logic can use one canonical name
# original_cmd is kept for suffix stripping (e.g. "- VIM", "- NVIM")
original_cmd="$cmd"
cmd="$(normalize_cmd "$cmd")"

# Disambiguate before icon lookup so command_icon stays a pure case statement
# Hermes runs via python3/uv/pip but should show 🧠, not 🐍
if [[ "$cmd" =~ ^(python3|python|uv|pip)$ ]] && echo "$title" | grep -qi 'hermes'; then
    cmd='hermes'
fi

# When hermes is launched from fish (via hermes.fish wrapper), pane_current_command
# shows fish, not the underlying python3 process. Check process tree for hermes.
if [[ "$cmd" == fish ]]; then
    pane_pid="$(tmux display-message -p -t "$pane_id" '#{pane_pid}' 2>/dev/null)"
    if [[ -n "$pane_pid" ]] && pstree -p "$pane_pid" 2>/dev/null | grep -qi 'hermes'; then
        cmd='hermes'
    fi
fi

# --- icon + title mode ---
icon="$(command_icon "$cmd")"
title_mode="$(command_title_mode "$cmd")"

if [[ "$title" =~ ^\[([^]]+)\][[:space:]]*(.*)$ ]]; then
    remote="$(host_label "${BASH_REMATCH[1]}")"
    remote_title="${BASH_REMATCH[2]}"

    remote_original_cmd="${remote_title%% *}"
    remote_cmd="$(normalize_cmd "$remote_original_cmd")"
    remote_icon="$(command_icon "$remote_cmd")"
    remote_title_mode="$(command_title_mode "$remote_cmd")"

    if [[ "$cmd" == ssh || "$cmd" == scp ]] && [[ "$remote_icon" == "$remote_cmd" && -z "$remote_title_mode" ]]; then
        if [[ -n "$remote_title" ]]; then
            printf '📡 %s %s' "$remote" "$remote_title"
        else
            printf '📡 %s' "$remote"
        fi
        exit 0
    fi

    if [[ "$remote_title_mode" == short ]]; then
        remote_info="$(short_title "$remote_title" "$remote_cmd" "$remote_original_cmd")"
    else
        remote_info="${remote_title#"$remote_original_cmd"}"
        remote_info="${remote_info#"${remote_info%%[![:space:]]*}"}"
    fi

    if [[ -n "$remote_info" ]]; then
        printf '📡 %s %s %s' "$remote" "$remote_icon" "$remote_info"
    else
        printf '📡 %s %s' "$remote" "$remote_icon"
    fi
    exit 0
fi

# --- info ---
if [[ "$title_mode" == remote ]]; then
    remote_title="${title#$cmd }"        # strip leading "cmd " if present
    remote_title="${remote_title% - ${original_cmd^^}}"
    if [[ "$remote_title" =~ ^\[([^]]+)\][[:space:]]*(.*)$ ]]; then
        remote="$(host_label "${BASH_REMATCH[1]}")"
        remote_path="${BASH_REMATCH[2]}"
    else
        remote="${remote_title%% *}"
        remote_path="${remote_title#"$remote"}"
        remote_path="${remote_path#"${remote_path%%[![:space:]]*}"}"
        remote="${remote#\[}"
        remote="${remote%\]}"
        remote="$(host_label "$remote")"
    fi
    if [[ -n "$remote_path" ]]; then
        info="$remote $remote_path"
    else
        info="$remote"
    fi
elif [[ "$title_mode" == short ]]; then
    info="$(short_title "$title" "$cmd" "$original_cmd")"
else
    display="${path/$HOME/\~}"
    if [[ "$display" != */* ]]; then
        # path is $HOME itself or a single-component path like /tmp
        info="$display"
    else
        base="${display##*/}"
        parent_path="${display%/*}"
        parent="${parent_path##*/}"
        if [[ -z "$parent" ]]; then
            candidate="/$base"         # e.g. /tmp
        else
            candidate="$parent/$base"  # e.g. ~/bin or projects/myapp
        fi
        if [[ ${#candidate} -lt 20 ]]; then
            info="$candidate"
        else
            info="$base"
        fi
    fi
fi

# ponytail: local agents only — behind ssh cmd is "ssh", no badge there
badge=""
if [[ -n "$pane_id" && "$cmd" =~ ^(claude|hermes|pi|copilot|cursor-agent)$ ]]; then
    pane_text="$(tmux capture-pane -p -t "$pane_id" 2>/dev/null | tail -n 20)"
    state="$(agent_state "$cmd" "$title" "$pane_text")"

    # "Done while you were away": working→idle edge in a non-current window
    # sets @agent_done; rendering as the current window clears it (= seen).
    # State lives in pane user options, dies with the pane.
    # ponytail: 5s poll is the debounce — a working→idle flicker across a
    # tick can false-ring; store two prev states if it ever annoys.
    prev="$(tmux show -pqvt "$pane_id" @agent_prev 2>/dev/null)"
    tmux set -pt "$pane_id" @agent_prev "$state" 2>/dev/null
    if [[ "$is_current" == 1 ]]; then
        tmux set -pt "$pane_id" -u @agent_done 2>/dev/null
    elif [[ "$prev" == working && "$state" == idle ]]; then
        tmux set -pt "$pane_id" @agent_done 1 2>/dev/null
    fi

    # One-shot desktop alerts on state edges (not every status refresh).
    if [[ -n "$prev" ]]; then
        case "$cmd" in
            cursor-agent) agent_name='Cursor Agent' ;;
            claude)         agent_name='Claude' ;;
            hermes)         agent_name='Hermes' ;;
            copilot)        agent_name='Copilot' ;;
            pi)             agent_name='Pi' ;;
        esac
        win_idx="$(tmux display-message -p -t "$pane_id" '#{window_index}' 2>/dev/null)"
        notify_body="tmux window ${win_idx:-?} · ${info:-$path}"
        if [[ "$prev" != blocked && "$state" == blocked ]]; then
            TOAST_FORCE=1 TOAST_DURATION=8000 agent_toast '🔔' "$agent_name needs your input — $notify_body"
        elif [[ "$is_current" != 1 && "$prev" == working && "$state" == idle ]]; then
            TOAST_DURATION=5000 agent_toast '💡' "$agent_name finished — $notify_body"
        fi
    fi

    case "$state" in
        blocked) badge='🔔' ;;
        working) badge='👀' ;;
        idle)    [[ "$is_current" != 1 && -n "$(tmux show -pqvt "$pane_id" @agent_done 2>/dev/null)" ]] && badge='💡' ;;
    esac
fi

printf '%s%s %s' "$badge" "$icon" "$info"
