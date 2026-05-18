function maintenance_pc
    if not type -q tsp
        echo "🚫 Skipping maintenance_pc: tsp is not available on PATH" >&2
        return 1
    end

    if not type -q go
        echo "🚫 Skipping maintenance_pc: go is not available on PATH" >&2
        return 1
    end

    tsp fish -c "go install github.com/paranoidi/paras-commander/cmd/pc@latest" > /dev/null
end
