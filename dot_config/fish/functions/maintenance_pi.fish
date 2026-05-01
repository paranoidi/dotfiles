function maintenance_pi
    if not type -q tsp
        echo "🚫 Skipping maintenance_pi: tsp is not available on PATH" >&2
        return 1
    end

    if type -q nvm
        # Keep JS packages seven days old since supply chains move fast.
        tsp fish -c "nvm use latest && npm install --min-release-age=7 -g @mariozechner/pi-coding-agent" > /dev/null
    else
        echo "🚫 nvm is not installed on this machine"
    end
end
