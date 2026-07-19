function _snapshot_home --description 'Snapshot home directory via tsp if available'
    if not type -q snapshot-home
        return
    end

    if type -q tsp
        tsp snapshot-home >/dev/null
    else
        snapshot-home
    end
end
