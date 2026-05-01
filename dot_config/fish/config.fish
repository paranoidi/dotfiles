# Source local.fish if it exists.
if test -f (dirname (status -f))/local.fish
    source (dirname (status -f))/local.fish
end

# Run for SSH login shells.
if status --is-login; and set -q SSH_CONNECTION
    if type -q fastfetch
        fastfetch
    else if type -q neofetch
        neofetch
    else
        uptime
    end
end

# Disable history when agent is running.
if set -q CURSOR_AGENT; and not set -q CLAUDECODE
    set -g fish_history ""
end
