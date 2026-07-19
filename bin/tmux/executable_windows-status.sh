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
        du)                     printf '📊' ;;
        pi|llm|aichat|copilot)  printf '🧠' ;;
        bat|less)               printf '📃' ;;
        apt)                    printf '🔧' ;;
        man)                    printf '📖' ;;
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
            if [[ "$title" =~ ^[⠀-⣿]\  ]]; then
                printf 'working'
            elif [[ "$text" == *'do you want to proceed?'* ]] ||
                 { [[ "$text" == *'esc to cancel'* ]] && [[ "$text" == *'enter to select'* ]]; }; then
                printf 'blocked'
            else
                printf 'idle'
            fi ;;
        hermes)
            if [[ "$text" == *'dangerous command'* || "$text" == *'allow once'* ]]; then
                printf 'blocked'
            elif [[ "$text" == *'msg=interrupt'* || "$text" == *'ctrl+c cancel'* ]]; then
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

if [[ "$1" == --test ]]; then
    t() { local want="$1"; shift; local got; got="$(agent_state "$@")"
          [[ "$got" == "$want" ]] || { echo "FAIL: agent_state $* -> '$got', want '$want'"; exit 1; }; }
    t working claude '⠐ fix parser' ''
    t blocked claude '✳ fix parser' $'Bash command\nDo you want to proceed?\n ❯ 1. Yes'
    t blocked claude '✳ fix parser' $'Enter to select · Esc to cancel'
    t idle    claude '✳ fix parser' $'❯ '
    t blocked hermes '' 'Allow once   Allow for this session   Deny'
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

    case "$state" in
        blocked) badge='🔔' ;;
        working) badge='👀' ;;
        idle)    [[ "$is_current" != 1 && -n "$(tmux show -pqvt "$pane_id" @agent_done 2>/dev/null)" ]] && badge='💡' ;;
    esac
fi

printf '%s%s %s' "$badge" "$icon" "$info"
