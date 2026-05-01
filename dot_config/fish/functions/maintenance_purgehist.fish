function maintenance_purgehist
    if not type -q tsp
        echo "🚫 Skipping maintenance_purgehist: tsp is not available on PATH" >&2
        return 1
    end

    tsp rmhist -s '^(sgpt|aichat|git commit)' > /dev/null
    tsp rmhist -s '^(ls|cd\s\.\.)$' > /dev/null
end
