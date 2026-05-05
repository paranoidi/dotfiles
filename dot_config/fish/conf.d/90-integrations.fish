# Use starship prompt if installed.
if type -q starship; and not set -q CURSOR_AGENT; and not set -q CLAUDECODE
    starship init fish | source
end

# Enable direnv.
if type -q direnv
    eval (direnv hook fish)
end

# Enable amoxide
if type -q am
    am init fish | source
end