#!/usr/bin/env bash
# tmux-window-status cmd title path pane_id
# Outputs: "<icon> <info>" for one window status entry.
# Arguments passed from .tmux.conf:
#   $1  pane_current_command
#   $2  pane_title
#   $3  pane_current_path
#   $4  pane_id (for agent detection + state capture; optional)
#   $5  1 if this is the current window (clears the "done" flag), else 0/empty
# Self-check: windows-status.sh --test

cmd="$1"
title="$2"
path="$3"
pane_id="$4"
is_current="$5"

# Supported agents: command name → display name. The single list every
# agent check (detection, state, badge, toast) goes through.
declare -A AGENT_NAME=([claude]=Claude [hermes]=Hermes [pi]=Pi [copilot]=Copilot [cursor-agent]='Cursor Agent')
is_agent() { [[ -n "$1" && -n "${AGENT_NAME[$1]+x}" ]]; }

# --- small string helpers ---

ltrim() { printf '%s' "${1#"${1%%[![:space:]]*}"}"; }

# Join the non-empty args with single spaces.
words() {
    local out=() a
    for a; do [[ -n "$a" ]] && out+=("$a"); done
    printf '%s' "${out[*]}"
}

# "[host] rest" → globals host (via host_label) + rest; fails if no [host] prefix.
parse_bracket_host() {
    [[ "$1" =~ ^\[([^]]+)\][[:space:]]*(.*)$ ]] || return 1
    host="$(host_label "${BASH_REMATCH[1]}")"
    rest="${BASH_REMATCH[2]}"
}

# Drop a leading "cmd " / "original_cmd " and the trailing " - CMD" suffix
# vim/nvim put in their titles (" - VIM", " - NVIM").
strip_cmd() {
    local s="${1#"$2 "}"
    s="${s#"$3 "}"
    printf '%s' "${s% - ${3^^}}"
}

# --- lookup tables ---

normalize_cmd() {
    case "$1" in batcat) printf 'bat' ;; vim|nvim) printf 'vi' ;; git-*) printf 'git' ;; *) printf '%s' "$1" ;; esac
}

# Prints the icon; fails (prints nothing) for unknown commands.
command_icon() {
    case "$1" in
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
        eza|mc|pc)              printf '📜' ;;
        vi|hx)                  printf '🧬' ;;
        rm)                     printf '💀' ;;
        du|htop)                printf '📊' ;;
        pi|llm|aichat|copilot)  printf '🧠' ;;
        bat|less)               printf '📃' ;;
        apt)                    printf '🔧' ;;
        man)                    printf '📖' ;;
        "./pc")                 printf '👨‍💻' ;;
        *)                      return 1 ;;
    esac
}

# How the info part is derived from the title (default: from the path).
command_title_mode() {
    case "$1" in
        ssh|scp)                printf 'remote' ;;
        vi|bat|less|man)        printf 'short' ;;
        hx)                     printf 'helix' ;;
    esac
}

# Known hosts get their own icon; unknown ones fall back to 📡 + short name.
# Note: value is shortened by default fish_title to 10 characters
host_label() {
    case "$1" in
        hime)                   printf '🍰' ;;
        raspberryp)             printf '🍇' ;;
        mamoru)                 printf '🔦' ;;
        yokai)                  printf '👹' ;;
        prox)                   printf ' ' ;;
        orochi)                 printf '🚗' ;;
        *)                      printf '📡 %s' "${1:0:4}" ;;
    esac
}

# Path → icon replacement. Keyed on the display path ("~/..." form),
# glob match, first hit wins — extend with your own dirs.
path_icon() {
    case "$1" in
        *projects/homelab*)     printf '🧪' ;;
        *)                      return 1 ;;
    esac
}

# Same shape as path_icon, but applied only to agent panes (any state):
# replaces the path info with a project icon — extend with your own dirs.
agent_path_icon() {
    case "$1" in
        *paras-commander*)      printf '👨‍💻' ;;
        *flexget*)              printf '🛜' ;;
        *)                      return 1 ;;
    esac
}

# --- info formatters ---

# Display path → "parent/base" (or just base when that's 20+ chars),
# unless path_icon maps it.
path_info() {
    local display="$1" base parent candidate
    if path_icon "$display"; then
        return
    elif [[ "$display" != */* ]]; then
        # path is $HOME itself or a single-component path like /tmp
        printf '%s' "$display"
        return
    fi
    base="${display##*/}"
    parent="${display%/*}"
    parent="${parent##*/}"
    if [[ -z "$parent" ]]; then
        candidate="/$base"         # e.g. /tmp
    else
        candidate="$parent/$base"  # e.g. ~/bin or projects/myapp
    fi
    if [[ ${#candidate} -lt 20 ]]; then
        printf '%s' "$candidate"
    else
        printf '%s' "$base"
    fi
}

short_title() {
    local s
    s="$(strip_cmd "$1" "$2" "$3")"
    printf '%s' "${s% [~\/]*}"       # strip trailing path-like word
}

# Helix sets no OSC title, so fish_title supplies "vi <file> <short-cwd>".
# Show "dir/file": from the file arg when it carries a path, else
# last(cwd) + filename. ponytail: single `<file>` arg only.
helix_info() {
    local title="$1" display="$2" f dir
    f="${title#* }"; f="${f%% *}"
    if [[ "$f" == */* ]]; then
        dir="${f%/*}"
        printf '%s/%s' "${dir##*/}" "${f##*/}"
    else
        printf '%s/%s' "${display##*/}" "$f"
    fi
}

# --- agent detection ---

# Reads `ps -o tpgid=,pgid=,args=` lines; prints the first agent in the
# foreground job (pgid == tty's tpgid). Like herdr's identify_agent_in_job,
# but matching argv words too, so wrappers (bash claude-update.sh,
# hermes.fish) and interpreters (python3 .../hermes, uv run hermes) resolve.
# ponytail: checks the first 3 argv words by basename — node agents whose
# script isn't named after the agent (claude/cli.js) still read as node.
foreground_agent() {
    awk -v agents="${!AGENT_NAME[*]}" '
        BEGIN { n = split(agents, a, " "); for (i = 1; i <= n; i++) ok[a[i]] = 1 }
        $1 == $2 {
            for (i = 3; i <= 5 && i <= NF; i++) {
                w = $i; sub(/.*\//, "", w)
                if (w in ok) { print w; exit }
            }
        }'
}

# Claude screen-text working fallbacks for when the OSC spinner title is
# unavailable/stale — ported from herdr's live_turn_working /
# background_agents_working rules (src/detect/manifests/claude.toml,
# commit a05c4038). herdr dropped the old "N shells" working guess
# (987b070f, false positive: background shells != Claude working) and
# added the ✳ (U+2733) spinner glyph to the activity-line char class
# (a05c4038) — both ported here.
claude_screen_working() {
    local text="$1" line
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*[⏸⏵].*esc[[:space:]]to[[:space:]]interrupt([[:space:]]|·|$) ]] && return 0
        [[ "$line" =~ ^[[:space:]]*[*·✢✳✶✻✽][[:space:]]+[^[:space:]].*…([[:space:]]+\([0-9]+[smh]([[:space:]]|·)|[[:space:]]*$) ]] && return 0
        [[ "$line" =~ ^[[:space:]]*[*·✢✶✻✽][[:space:]]+waiting[[:space:]]for[[:space:]][1-9][0-9]*[[:space:]]background[[:space:]]agents?[[:space:]]to[[:space:]]finish[[:space:]]*$ ]] && return 0
    done <<< "$text"
    return 1
}

# herdr's background_mcp_task_working (src/detect/manifests/claude.toml,
# f72a5ef9): an activity line ending "· N MCP task(s) still running" also
# counts as working. herdr excludes this when a permission/blocked prompt
# is also on screen so that state wins instead; same exclusions here.
# ponytail: single-line match only (herdr's regex also spans up to 4
# wrapped continuation lines) — extend if a real wrapped case misfires.
claude_mcp_task_working() {
    local text="$1" line
    case "$text" in
        *'do you want to proceed?'*|*'esc to cancel'*|*'waiting for permission'*| \
        *'do you want to allow this connection?'*|*'tab to amend'*|*'ctrl+e to explain'*)
            return 1 ;;
    esac
    while IFS= read -r line; do
        [[ "$line" =~ ^[*·✢✶✻✽][[:space:]]+[^[:space:]].*·[[:space:]]+[1-9][0-9]*[[:space:]]+mcp[[:space:]]+tasks?[[:space:]]+still[[:space:]]+running[[:space:]]*$ ]] && return 0
    done <<< "$text"
    return 1
}

# herdr's mcp_elicitation_prompt (src/detect/manifests/claude.toml,
# f807b697): MCP elicitation dialogs show Accept/Decline with an
# "esc to cancel" footer but no "enter to select" hint, so the generic
# blocked check below misses them.
claude_mcp_elicitation_blocked() {
    local text="$1"
    [[ "$text" == *'esc to cancel'* ]] || return 1
    [[ "$text" =~ mcp\ server\ .+\ requests\ your\ input ]] || return 1
    [[ "$text" == *'accept'* || "$text" == *'decline'* ]] || return 1
    return 0
}

# herdr's legacy_no_prompt_blocker (src/detect/manifests/claude.toml, prio 300).
# Catches the plan-approval dialog ("Would you like to proceed?" + numbered
# options, no esc/enter footer), which no other blocked rule sees.
# herdr's live_prompt_box idle (950) outranks it; approximated by bailing when
# a ❯ line is the input prompt rather than a numbered option ("❯ 1. Yes").
claude_legacy_blocked() {
    local text="$1" line
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*❯ && ! "$line" =~ ^[[:space:]]*❯[[:space:]]*[0-9]+\. ]] && return 1
    done <<< "$text"
    [[ ( "$text" == *'do you want to'* || "$text" == *'would you like to'* ) &&
       ( "$text" == *yes* || "$text" == *❯* ) ]] && return 0
    [[ "$text" == *'waiting for permission'* || "$text" == *'do you want to allow this connection?'* ||
       "$text" == *'tab to amend'* || "$text" == *'ctrl+e to explain'* ||
       "$text" == *'review your answers'* || "$text" == *'skip interview and plan immediately'* ]]
}

# Agent state from (title, bottom-of-screen text). Rules ported from
# herdr's src/detect/manifests/{claude,hermes,github-copilot,pi}.toml.
# Prints: working | blocked | idle
agent_state() {
    local cmd="$1" title="$2" text="${3,,}"    # lowercase text, herdr matches case-insensitively
    case "$cmd" in
        claude)
            # herdr priority: spinner title (1100) > screen working fallbacks
            # (970/965) > screen blockers (850-980) > idle
            # Spinner glyph: braille (⠀-⣿, old CLI versions) or circleHalves (◐◑◒◓, current)
            if [[ "$title" =~ ^[⠀-⣿◐◑◒◓]\  ]]; then
                printf 'working'
            elif claude_screen_working "$text"; then
                printf 'working'
            elif claude_mcp_task_working "$text"; then
                printf 'working'
            elif claude_mcp_elicitation_blocked "$text"; then
                printf 'blocked'
            elif [[ "$text" == *'do you want to proceed?'* ]] ||
                 { [[ "$text" == *'esc to cancel'* ]] && [[ "$text" == *'enter to select'* ]]; } ||
                 claude_legacy_blocked "$text"; then
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

# Two-tick idle confirmation: a bare working->idle read can be a one-tick
# flicker (e.g. mid-subagent render gap where no rule matches "working" for
# an instant) rather than a real finish. herdr hit the same false-done bug
# and fixed it with a pending-idle confirmation window (src/pane/agent_detection.rs,
# PendingIdleConfirmation) — this is that idea, adapted to poll-per-tick
# instead of herdr's sub-second recheck loop.
# Prints "<new_pending> <fire>"; fire=1 only on the tick that confirms idle.
idle_debounce() {
    local prev="$1" pending="$2" state="$3"
    if [[ "$state" != idle ]]; then
        printf '0 0'
    elif [[ "$prev" == working ]]; then
        printf '1 0'
    elif [[ "$prev" == idle && "$pending" == 1 ]]; then
        printf '0 1'
    else
        printf '0 0'
    fi
}

# --- tmux / desktop side effects ---

popt_get() { tmux show -pqvt "$pane_id" "$1" 2>/dev/null; }
popt_set() { tmux set -pt "$pane_id" "$@" 2>/dev/null; }

# agent_toast icon duration_ms force(0|1) msg
# Desktop/tmux toast via fish; tmux-only fallback when fish is unavailable.
agent_toast() {
    local icon="$1" duration="$2" force="$3" msg="$4"
    if command -v fish >/dev/null 2>&1; then
        fish -c '
            set -l flags -d $argv[2]
            test "$argv[3]" = 1; and set -a flags -f
            toast -i $argv[1] $flags -- $argv[4]
        ' "$icon" "$duration" "$force" "$msg" 2>/dev/null &
    elif command -v tmux >/dev/null 2>&1; then
        tmux display-message " $icon $msg" 2>/dev/null &
    fi
}

if [[ "$1" == --test ]]; then
    check() { local want="$1"; shift; local got; got="$("$@")"
              [[ "$got" == "$want" ]] || { echo "FAIL: $* -> '$got', want '$want'"; exit 1; }; }
    check working agent_state claude '⠐ fix parser' ''
    check working agent_state claude '◐ fix parser' ''
    check idle    agent_state claude '✳ fix parser' ''
    check blocked agent_state claude '✳ fix parser' $'Bash command\nDo you want to proceed?\n ❯ 1. Yes'
    check blocked agent_state claude '✳ fix parser' $'Enter to select · Esc to cancel'
    check idle    agent_state claude '✳ fix parser' $'❯ '
    check working agent_state claude '' '⏵ esc to interrupt'
    check working agent_state claude '' '* Fetching data… (12s · esc to interrupt)'
    check working agent_state claude '' '✻ Thinking…'
    check working agent_state claude '' '⏸ Running · 2 shells · esc to interrupt'
    check idle    agent_state claude '' '⏸ Running · 2 shells ·'
    check working agent_state claude '' '✳ Fetching data… (12s · esc to interrupt)'
    check working agent_state claude '' '* Waiting for 3 background agents to finish'
    check working agent_state claude '' '* Running research · 2 MCP tasks still running'
    check blocked agent_state claude '' $'MCP server "figma" requests your input\n❯ Accept\n  Decline\nEsc to cancel'
    check idle    agent_state claude '' '* just some text'
    check blocked agent_state claude '✳ add bye' $'Claude has written up a plan and is ready to execute. Would you like to proceed?\n\n ❯ 1. Yes, manually approve edits\n   2. Tell Claude what to change\n\n ctrl+g to edit in Hx · ~/.claude/plans/x.md'
    check idle    agent_state claude '✳ add bye' $'would you like to proceed? yes\n────\n❯ \n────'
    check blocked agent_state hermes '⚠ auth error' ''
    check working agent_state hermes '⏳ thinking' ''
    check idle    agent_state hermes '✓ done' ''
    check blocked agent_state hermes '' $'Dangerous command\nAllow once   Deny\nEnter confirm'
    check blocked agent_state hermes '' $'Hermes needs your input\nPress enter'
    check blocked agent_state hermes '' $'ask what filename?\nEnter send'
    check blocked agent_state hermes '' 'sudo password:'
    check blocked agent_state hermes '' $'Approve once   Cancel\nEnter to confirm'
    check working agent_state hermes '' 'ctrl+c to interrupt'
    check working agent_state hermes '' 'esc … ctrl+c cancel'
    check idle    agent_state hermes '' 'hermes> '
    check blocked agent_state copilot '' 'Enter to select · Esc to cancel'
    check working agent_state copilot '' 'Esc to cancel'
    check idle    agent_state copilot '' '> '
    check working agent_state pi '' 'Working...'
    check idle    agent_state pi '' 'pi> '
    check blocked agent_state cursor-agent '' 'Run this command? Run (once) (y)  Skip (esc or n)'
    check working agent_state cursor-agent '' 'Ctrl+C to stop'
    check working agent_state cursor-agent '' '⬢ Generating response'
    check idle    agent_state cursor-agent '' '> '
    check '0 0' idle_debounce working 0 working    # still working: no pending, no fire
    check '1 0' idle_debounce working 0 idle       # first idle tick after working: arm, don't fire yet
    check '0 1' idle_debounce idle 1 idle          # second consecutive idle tick: confirmed
    check '0 0' idle_debounce idle 0 idle          # already confirmed earlier: don't re-fire
    check '0 0' idle_debounce idle 1 working       # work resumed before confirmation: flicker absorbed
    check '🧪' path_icon '~/projects/homelab'
    check ''   path_icon '~/projects/foo'          # no match → nothing
    check '👨‍💻' agent_path_icon '~/projects/paras-commander'
    check ''   agent_path_icon '~/projects/other'
    check '🧪'      path_info '~/projects/homelab/x'
    check '~'       path_info '~'
    check '/tmp'    path_info '/tmp'
    check 'bin/tmux' path_info '~/bin/tmux'
    check 'averyveryverylongname' path_info '~/projects/averyveryverylongname'
    check 'tmux/windows-status.sh' helix_info 'vi windows-status.sh ~/b/tmux' '~/bin/tmux'
    check 'tmux/windows-status.sh' helix_info 'windows-status.sh' '~/bin/tmux'
    check 'src/main.rs' helix_info 'vi src/main.rs ~/b/tmux' '~/bin/tmux'
    check 'x/hx' helix_info 'vi hx ~/b/tmux' '~/bin/x'
    check 'foo.txt' short_title 'nvim foo.txt - NVIM' vi nvim
    check 'foo.txt' short_title 'vim foo.txt ~/x' vi vim
    check 'bash'    short_title 'man bash' man man
    check '🍰'      host_label hime
    check '📡 some' host_label somehost
    check ''     command_icon nosuchcmd
    check 'a b'  words '' a '' b
    check 'x y'  ltrim '  x y'
    check claude foreground_agent <<< $'100 100 bash claude-update.sh\n100 100 /home/u/.local/bin/claude --x'
    check hermes foreground_agent <<< '100 100 python3 /home/u/.local/bin/hermes'
    check hermes foreground_agent <<< '100 100 uv run hermes'
    check ''     foreground_agent <<< $'100 100 -fish\n100 200 claude'   # claude not in foreground job
    check ''     foreground_agent <<< '100 100 python3 script.py --x pi' # beyond argv[3]
    echo OK
    exit 0
fi

# --- main ---

# Normalize aliases so icon + title-strip logic use one canonical name;
# original_cmd is kept for suffix stripping (e.g. "- VIM", "- NVIM").
original_cmd="$cmd"
cmd="$(normalize_cmd "$cmd")"
display="${path/#$HOME/\~}"

if [[ -n "$pane_id" ]]; then
    read -r pane_tty win_idx <<< "$(tmux display-message -p -t "$pane_id" '#{pane_tty} #{window_index}' 2>/dev/null)"
    # Shells/interpreters may be hosting an agent (wrapper script, python hermes).
    if [[ -n "$pane_tty" && "$cmd" =~ ^(bash|sh|dash|zsh|fish|python3|python|uv|pip|node)$ ]]; then
        job_agent="$(ps -o tpgid=,pgid=,args= -t "${pane_tty#/dev/}" 2>/dev/null | foreground_agent)"
        [[ -n "$job_agent" ]] && cmd="$job_agent"
    fi
fi

icon="$(command_icon "$cmd")" || icon="$cmd"
title_mode="$(command_title_mode "$cmd")"

# Local windows lead with this machine's host icon (none if it has no icon).
# fish_title truncates to 10 chars, see host_label.
local_host="$(host_label "${HOSTNAME:0:10}")"
[[ "$local_host" == 📡* ]] && local_host=""

# fish_title prefixes "[host]" locally too; drop it for this machine
if [[ "$title" =~ ^\[([^]]+)\][[:space:]]*(.*)$ && "${BASH_REMATCH[1]}" == "${HOSTNAME:0:10}" ]]; then
    title="${BASH_REMATCH[2]}"
fi

# Title "[host] remote-title": a remote shell's fish_title, seen through ssh.
if parse_bracket_host "$title"; then
    remote_original_cmd="${rest%% *}"
    remote_cmd="$(normalize_cmd "$remote_original_cmd")"
    remote_title_mode="$(command_title_mode "$remote_cmd")"
    if ! remote_icon="$(command_icon "$remote_cmd")"; then
        # Unknown remote program over ssh (usually a bare path): show it verbatim
        if [[ "$title_mode" == remote && -z "$remote_title_mode" ]]; then
            words "$host" "$rest"
            exit 0
        fi
        remote_icon="$remote_cmd"
    fi
    if [[ "$remote_title_mode" == short ]]; then
        remote_info="$(short_title "$rest" "$remote_cmd" "$remote_original_cmd")"
    else
        remote_info="$(ltrim "${rest#"$remote_original_cmd"}")"
    fi
    words "$host" "$remote_icon" "$remote_info"
    exit 0
fi

case "$title_mode" in
    remote)
        # "ssh host path" / "ssh [host] path"
        t="$(strip_cmd "$title" "$cmd" "$original_cmd")"
        if ! parse_bracket_host "$t"; then
            h="${t%% *}"
            rest="$(ltrim "${t#"$h"}")"
            h="${h#\[}"
            host="$(host_label "${h%\]}")"
        fi
        # remote host label replaces the ssh icon and the local host icon
        icon="$host"
        local_host=""
        info="$rest" ;;
    short) info="$(short_title "$title" "$cmd" "$original_cmd")" ;;
    helix) info="$(helix_info "$title" "$display")" ;;
    *)     info="$(path_info "$display")" ;;
esac

# ponytail: local agents only — behind ssh cmd is "ssh", no badge there
badge=""
if [[ -n "$pane_id" ]] && is_agent "$cmd"; then
    pane_text="$(tmux capture-pane -p -t "$pane_id" 2>/dev/null | tail -n 20)"
    state="$(agent_state "$cmd" "$title" "$pane_text")"

    # "Done while you were away": working→idle edge in a non-current window
    # sets @agent_done; rendering as the current window clears it (= seen).
    # State lives in pane user options, dies with the pane.
    # ponytail: idle must be confirmed for 2 polls (idle_debounce) before it
    # counts as "done" — a single flicker (e.g. mid-subagent render gap)
    # otherwise false-rings. Raise the confirmation count further if it
    # still false-rings on a slower poll interval.
    prev="$(popt_get @agent_prev)"
    read -r new_pending idle_confirmed <<< "$(idle_debounce "$prev" "$(popt_get @agent_pending_idle)" "$state")"
    popt_set @agent_prev "$state"
    popt_set @agent_pending_idle "$new_pending"
    agent_done="$(popt_get @agent_done)"
    if [[ "$is_current" == 1 ]]; then
        agent_done=''
        popt_set -u @agent_done
    elif [[ "$idle_confirmed" == 1 ]]; then
        agent_done=1
        popt_set @agent_done 1
    fi

    # One-shot desktop alerts on state edges (not every status refresh).
    if [[ -n "$prev" ]]; then
        agent_name="${AGENT_NAME[$cmd]}"
        notify_body="tmux window ${win_idx:-?} · ${info:-$path}"
        if [[ "$prev" != blocked && "$state" == blocked ]]; then
            agent_toast '🔔' 8000 1 "$agent_name needs your input — $notify_body"
        elif [[ "$is_current" != 1 && "$idle_confirmed" == 1 ]]; then
            agent_toast '💡' 5000 0 "$agent_name finished — $notify_body"
        fi
    fi

    case "$state" in
        blocked) badge='🔔' ;;
        working) badge='👀' ;;
        idle)    [[ -n "$agent_done" ]] && badge='💡' ;;
    esac
    # Agent pane in a mapped dir: path info → project icon
    if aip="$(agent_path_icon "$display")"; then
        info="$aip"
    fi
fi

words "$local_host" "$badge$icon" "$info"
