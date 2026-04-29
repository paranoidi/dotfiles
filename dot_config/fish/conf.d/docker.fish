# =============================================================================
# Docker fzf helpers
# Provides: dps, dshell, dstop, dclean, dexec, dhelp
#           _fzf_search_docker (Ctrl-Alt-D commandline widget)
#           __docker_check, __docker_pick (private)
# =============================================================================

function __docker_check --description "Verify docker is installed and the daemon is reachable"
    if not command -q docker
        echo "docker: command not installed" >&2
        return 127
    end

    if not docker info >/dev/null 2>&1
        echo "docker daemon not reachable — is it running?" >&2
        return 1
    end
end

function dps --description "Pick docker container(s) via fzf, print selected id(s) to stdout"
    __docker_check; or return

    argparse --name=dps 'a/all' -- $argv
    or return

    set -l ps_args --format 'table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
    if set -q _flag_all
        set -p ps_args -a
    end

    set -l preview 'bash -c '\''
        cid=$1
        section() { local title=$1 body=$2; [[ "$body" =~ [^[:space:]] ]] && printf "\033[1;36m━━━ %s ━━━\033[0m\n%s\n" "$title" "$body"; }

        printf "\033[1;36m━━━ %s ━━━\033[0m\n" "$cid"
        docker inspect --format "Name:     {{.Name}}" "$cid" 2>/dev/null
        docker inspect --format "Image:    {{.Config.Image}}" "$cid" 2>/dev/null
        docker inspect --format "Status:   {{.State.Status}} (exit {{.State.ExitCode}}, restarts {{.RestartCount}})" "$cid" 2>/dev/null
        docker inspect --format "Started:  {{.State.StartedAt}}" "$cid" 2>/dev/null
        health=$(docker inspect --format "{{if .State.Health}}{{.State.Health.Status}}{{end}}" "$cid" 2>/dev/null)
        [[ -n "$health" ]] && echo "Health:   $health"
        cmd=$(docker inspect --format "{{.Path}} {{join .Args \" \"}}" "$cid" 2>/dev/null)
        [[ -n "${cmd// /}" ]] && echo "Cmd:      $cmd"
        ep=$(docker inspect --format "{{join .Config.Entrypoint \" \"}}" "$cid" 2>/dev/null)
        [[ -n "$ep" ]] && echo "Entry:    $ep"
        wd=$(docker inspect --format "{{.Config.WorkingDir}}" "$cid" 2>/dev/null)
        [[ -n "$wd" ]] && echo "WorkDir:  $wd"
        user=$(docker inspect --format "{{.Config.User}}" "$cid" 2>/dev/null)
        [[ -n "$user" ]] && echo "User:     $user"
        rp=$(docker inspect --format "{{.HostConfig.RestartPolicy.Name}}" "$cid" 2>/dev/null)
        [[ -n "$rp" && "$rp" != "no" ]] && echo "Restart:  $rp"
        echo ""

        nets=$(docker inspect --format "{{range \$k,\$v := .NetworkSettings.Networks}}{{\$k}}: {{\$v.IPAddress}}{{println}}{{end}}" "$cid" 2>/dev/null)
        section networks "$nets"
        ports=$(docker inspect --format "{{range \$p,\$b := .NetworkSettings.Ports}}{{\$p}}{{if \$b}} -> {{(index \$b 0).HostIp}}:{{(index \$b 0).HostPort}}{{end}}{{println}}{{end}}" "$cid" 2>/dev/null)
        section ports "$ports"
        mounts=$(docker inspect --format "{{range .Mounts}}{{.Type}}  {{.Source}} -> {{.Destination}}{{println}}{{end}}" "$cid" 2>/dev/null)
        section mounts "$mounts"
        env=$(docker inspect --format "{{range .Config.Env}}{{.}}{{println}}{{end}}" "$cid" 2>/dev/null | head -8)
        section "env (top 8)" "$env"

        stats=$(docker stats --no-stream --format "CPU: {{.CPUPerc}}  MEM: {{.MemUsage}} ({{.MemPerc}})  NET: {{.NetIO}}  BLOCK: {{.BlockIO}}" "$cid" 2>/dev/null)
        section stats "$stats"
    '\'' _ {1}'

    set -l logs_preview 'bash -c '\''
        cid=$1
        printf "\033[1;36m━━━ logs %s (live, Ctrl-R to stop) ━━━\033[0m\n" "$cid"
        docker logs --tail 200 -f "$cid" 2>&1
    '\'' _ {1}'

    set -l selected (
        docker ps $ps_args | \
        fzf --multi \
            --height=60% \
            --reverse \
            --border \
            --header-lines=1 \
            --ansi \
            --prompt="container> " \
            --header="Ctrl-L: logs · Ctrl-R: info · Ctrl-P: toggle preview" \
            --preview=$preview \
            --preview-window=right:60%:wrap \
            --bind="ctrl-p:toggle-preview" \
            --bind="ctrl-l:change-preview($logs_preview)+change-preview-window(right,60%,wrap,follow)" \
            --bind="ctrl-r:change-preview($preview)+change-preview-window(right,60%,wrap,nofollow)"
    )

    test $status -eq 0; or return

    for line in $selected
        echo (string split -f1 ' ' -- $line)
    end
end

function __docker_pick --description "Resolve a single running container id; auto-pick if exactly one filter match, otherwise fzf"
    set -l name_filter $argv[1]

    if test -n "$name_filter"
        set -l matches (docker ps --filter "name=$name_filter" --format '{{.ID}}')
        switch (count $matches)
            case 0
                echo "no running container matches name=$name_filter" >&2
                return 1
            case 1
                echo $matches[1]
                return 0
        end
    end

    set -l id (dps | head -n1)
    test -n "$id"; or return 1
    echo $id
end

function dexec --description "Pick a running container and run a command inside it (building block for custom wrappers)"
    __docker_check; or return

    argparse --name=dexec --ignore-unknown 'f/filter=' 'T/no-tty' 'w/workdir=' 'u/user=' -- $argv
    or return

    if test (count $argv) -eq 0
        echo "dexec: missing command (use -- to separate flags)" >&2
        echo "usage: dexec [-f NAME] [-T] [-w DIR] [-u USER] -- CMD [ARGS...]" >&2
        return 2
    end

    set -l id (__docker_pick $_flag_filter)
    or return

    set -l exec_args -i
    set -q _flag_no_tty; or set -a exec_args -t
    set -q _flag_workdir; and set -a exec_args -w $_flag_workdir
    set -q _flag_user; and set -a exec_args -u $_flag_user
    
    echo "📦 Running in $id: docker exec $exec_args $id $argv" >&2
    docker exec $exec_args $id $argv
end

function dshell --description "Pick a running container via fzf and open an interactive shell"
    __docker_check; or return

    set -l shell_cmd $argv[1]

    set -l id (dps | head -n1)
    or return

    test -n "$id"; or return

    echo "📦 Opening shell in $id (default: bash, fallback: sh)" >&2

    if test -n "$shell_cmd"
        docker exec -it $id $shell_cmd
        return $status
    end

    # Default: try bash, fall back to sh
    docker exec -it $id bash
    set -l rc $status
    if test $rc -ne 0
        echo "bash unavailable in $id (exit $rc), falling back to sh..." >&2
        docker exec -it $id sh
        return $status
    end
    return $rc
end

function dstop --description "Pick running container(s) via fzf and stop (or kill) them"
    __docker_check; or return

    argparse --name=dstop 'k/kill' -- $argv
    or return

    set -l ids (dps)
    or return

    test -n "$ids[1]"; or return

    set -l verb stop
    set -q _flag_kill && set verb kill

    echo "Running docker $verb on:"
    for id in $ids
        echo "  $id"
    end

    docker $verb $ids
end

function dclean --description "Interactively prune dangling images, stopped containers, and unused volumes"
    __docker_check; or return

    echo "━━━ docker disk usage ━━━"
    docker system df
    echo ""

    set -l dangling_count (docker images -f dangling=true -q | wc -l | string trim)
    set -l stopped_count (docker ps -a -f status=exited -f status=created -q | wc -l | string trim)
    set -l volume_count (docker volume ls -f dangling=true -q | wc -l | string trim)

    read -l -P "Prune $dangling_count dangling image(s)? [y/N] " ans
    if test "$ans" = y -o "$ans" = Y
        docker image prune -f
    end

    read -l -P "Prune $stopped_count stopped container(s)? [y/N] " ans
    if test "$ans" = y -o "$ans" = Y
        docker container prune -f
    end

    read -l -P "Prune $volume_count unused volume(s)? [y/N] " ans
    if test "$ans" = y -o "$ans" = Y
        docker volume prune -f
    end

    echo ""
    echo "━━━ after cleanup ━━━"
    docker system df
end

function dhelp --description "Show docker fzf helper commands and keybindings"
    echo "── DOCKER HELPERS ─────────────────────────────────────────────────────"
    echo ""
    echo "dps [-a|--all]            Pick container(s) via fzf, prints id(s) to stdout."
    echo "                          Default: running only. -a/--all includes stopped."
    echo "                          Multi-select: TAB. Use as a building block:"
    echo "                            set cid (dps); docker exec -it \$cid sh"
    echo ""
    echo "dshell [shell]            Pick a running container and open an interactive"
    echo "                          shell. Defaults to bash, falls back to sh."
    echo "                          Override: dshell zsh"
    echo ""
    echo "dstop [-k|--kill]         Pick running container(s) and docker stop them."
    echo "                          -k/--kill uses docker kill instead."
    echo ""
    echo "dclean                    Interactive cleanup with y/N prompts:"
    echo "                            • dangling images    (docker image prune)"
    echo "                            • stopped containers (docker container prune)"
    echo "                            • unused volumes     (docker volume prune)"
    echo "                          Shows docker system df before and after."
    echo ""
    echo "dexec [-f NAME] [-T] [-w DIR] [-u USER] -- CMD [ARGS...]"
    echo "                          Building block: pick (or auto-resolve) a running"
    echo "                          container and run CMD inside it."
    echo "                            -f/--filter NAME    only containers matching name"
    echo "                            -T/--no-tty         drop -t (for piping)"
    echo "                            -w/--workdir DIR    docker exec -w"
    echo "                            -u/--user USER      docker exec -u"
    echo ""
    echo "── CUSTOM WRAPPERS ────────────────────────────────────────────────────"
    echo ""
    echo "Define project-specific commands in conf.d/docker.private.fish"
    echo ""
    echo "  function dmysql; dexec -f db -- mysql -uroot -p\$argv; end"
    echo "  function dmanage; dexec -f web -- python manage.py \$argv; end"
    echo ""
    echo "── KEYBINDS ───────────────────────────────────────────────────────────"
    echo ""
    echo "Alt-D                     Open the docker fzf widget at the cursor and"
    echo "                          insert the chosen container into the commandline."
    echo "                            Enter   → container name"
    echo "                            Alt-I   → short container id"
    echo ""
    echo "── INSIDE THE FZF PICKER (dps and Alt-D) ───────────────────────────────"
    echo ""
    echo "TAB / Shift-TAB           Toggle multi-selection."
    echo "Ctrl-L                    Show live logs preview (docker logs -f, follow)."
    echo "Ctrl-R                    Switch back to info preview (inspect/networks/…)."
    echo "Ctrl-P                    Toggle the preview pane on/off."
    echo "Esc                       Cancel."
end

function _fzf_search_docker --description "Pick a docker container and insert its name (Enter) or short id (Alt-I) into the commandline"
    if not command -q docker
        echo >&2
        echo "docker: command not installed" >&2
        commandline --function repaint
        return
    end

    if not docker info >/dev/null 2>&1
        echo >&2
        echo "docker daemon not reachable — is it running?" >&2
        commandline --function repaint
        return
    end

    set -l preview 'bash -c '\''
        cid=$1
        section() { local title=$1 body=$2; [[ "$body" =~ [^[:space:]] ]] && printf "\033[1;36m━━━ %s ━━━\033[0m\n%s\n" "$title" "$body"; }

        printf "\033[1;36m━━━ %s ━━━\033[0m\n" "$cid"
        docker inspect --format "Name:    {{.Name}}" "$cid" 2>/dev/null
        docker inspect --format "Image:   {{.Config.Image}}" "$cid" 2>/dev/null
        docker inspect --format "Status:  {{.State.Status}}" "$cid" 2>/dev/null
        docker inspect --format "Started: {{.State.StartedAt}}" "$cid" 2>/dev/null
        echo ""

        nets=$(docker inspect --format "{{range \$k,\$v := .NetworkSettings.Networks}}{{\$k}}: {{\$v.IPAddress}}{{println}}{{end}}" "$cid" 2>/dev/null)
        section networks "$nets"
        ports=$(docker inspect --format "{{range \$p,\$b := .NetworkSettings.Ports}}{{\$p}}{{if \$b}} -> {{(index \$b 0).HostIp}}:{{(index \$b 0).HostPort}}{{end}}{{println}}{{end}}" "$cid" 2>/dev/null)
        section ports "$ports"
    '\'' _ {1}'

    set -l logs_preview 'bash -c '\''
        cid=$1
        printf "\033[1;36m━━━ logs %s (live, Ctrl-R to stop) ━━━\033[0m\n" "$cid"
        docker logs --tail 200 -f "$cid" 2>&1
    '\'' _ {1}'

    set -l result (
        begin
            printf 'ID\tNAMES\tIMAGE\tSTATUS\n'
            docker ps -a --format '{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}'
        end | \
        _fzf_wrapper --multi \
                     --height=60% \
                     --reverse \
                     --border \
                     --header-lines=1 \
                     --ansi \
                     --delimiter=\t \
                     --prompt="docker> " \
                     --expect=alt-i \
                     --header="Enter: name · Alt-I: id · Ctrl-L: logs · Ctrl-R: info · Ctrl-P: toggle" \
                     --preview=$preview \
                     --preview-window=right:60%:wrap \
                     --bind="ctrl-p:toggle-preview" \
                     --bind="ctrl-l:change-preview($logs_preview)+change-preview-window(right,60%,wrap,follow)" \
                     --bind="ctrl-r:change-preview($preview)+change-preview-window(right,60%,wrap,nofollow)" \
                     $fzf_docker_opts
    )

    test $status -eq 0; or begin
        commandline --function repaint
        return
    end

    # First line is the key pressed (empty for Enter, "alt-i" for Alt-I); rest are selections
    set -l key $result[1]
    set -l selections $result[2..]
    test (count $selections) -gt 0; or begin
        commandline --function repaint
        return
    end

    set -l tokens
    for line in $selections
        set -l fields (string split -n -- \t $line)
        if test "$key" = alt-i
            set -a tokens $fields[1]
        else
            set -a tokens $fields[2]
        end
    end

    commandline --current-token --replace -- (string join ' ' $tokens)
    commandline --function repaint
end

# Install Ctrl-Alt-D keybinding (interactive shells only)
if status is-interactive
    for mode in default insert
        bind --mode $mode \e\cD _fzf_search_docker
    end
end
