function maintenance_purgehist
    if not type -q tsp
        echo "🚫 Skipping maintenance_purgehist: tsp is not available on PATH" >&2
        return 1
    end

    tsp fish -c "rmhist -s '^(sgpt|aichat|git commit)'"
    tsp fish -c "rmhist -s '^(ls|cd\s\.\.|kill|murder)\$'"
end
