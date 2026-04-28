function __cz_modified_files
    chezmoi status | awk '$1 ~ /^[ M]/ {print $2}'
end

function __cz_deleted_files
    chezmoi status | awk '$1 ~ /^D/ {print $2}'
end

function __cz_import_changes
    set files (__cz_modified_files)

    if test (count $files) -eq 0
        echo "⚠️  No modified files"
        return 1
    end

    for f in $files
        echo "💾 $f"
        chezmoi add "$HOME/$f"
    end

    return 0
end

function cz

    set cmd $argv[1]

    if test -z "$cmd"
        set cmd help
    end

    switch $cmd

    # ------------------------------------------------------------
    # HELP
    # ------------------------------------------------------------
    case help
        echo "cz - chezmoi workflow helper"
        echo ""
        echo "Commands:"
        echo "  cz update (u)  → Pull latest state + apply to \$HOME"
        echo "  cz add (a)     → Add all local changes into chezmoi"
        echo "  cz status (s)  → Show status diff"
        echo "  cz diff (d)    → Show detailed diff"
        echo "  cz record (r)  → Add all changes + git commit [message]"
        echo "  cz push (p)    → Push commits to remote"
        echo "  cz full (f)    → Full sync cycle"
        return 0

    # ------------------------------------------------------------
    # UPDATE (repo → home)
    # ------------------------------------------------------------
    case update u
        echo "🌐 cz update"

        chezmoi update
        chezmoi apply

        echo "🏆 Update complete"
        return 0

    # ------------------------------------------------------------
    # ADD (home → repo)
    # ------------------------------------------------------------
    case add a
        echo "🛠️ cz add - Importing local changes into chezmoi"

        __cz_import_changes

        # deletion handling
        set deleted (__cz_deleted_files)
        if test (count $deleted) -gt 0
            echo ""
            echo "⚠️  deleted files detected:"
            for f in $deleted
                echo "  - $f"
            end

            read -P "❓ Remove these from chezmoi source as well? [y/N] " confirm
            if test "$confirm" = "y"
                for f in $deleted
                    echo "💀 $f"
                    chezmoi forget "$f"
                end
            end
        end

        echo "✅ Add complete"
        return 0

    # ------------------------------------------------------------
    # STATUS
    # ------------------------------------------------------------
    case status s
        echo "🛠️ cz status"
        chezmoi status
        return 0

    # ------------------------------------------------------------
    # DIFF
    # ------------------------------------------------------------
    case diff d
        echo "🛠️ cz diff"
        # Reverse diff direction so local additions appear as '+' (green).
        chezmoi diff --reverse
        return 0

    # ------------------------------------------------------------
    # RECORD (safe + smart)
    # ------------------------------------------------------------
    case record r
        echo "💾 cz record"

        set modified (__cz_modified_files)
        if test (count $modified) -gt 0
            __cz_import_changes
        end

        set deleted (__cz_deleted_files)

        if test (count $deleted) -gt 0
            echo ""
            echo "⚠️  Deleted files detected (not auto-handled in record):"
            for f in $deleted
                echo "  - $f"
            end
            echo "Run 'cz add' if you want to process deletions."
        end

        # check if anything actually staged in git
        if not chezmoi git -- status --porcelain | string length -q
            echo "ℹ️ Nothing to record"
            return 0
        end

        set msg (string join ' ' $argv[2..-1])
        if test -z "$msg"
            set msg "Update dotfiles"
        end

        chezmoi git -- add -A
        chezmoi git -- commit -m "$msg"

        echo "🏆 Recorded"
        return 0

    # ------------------------------------------------------------
    # PUSH (repo → remote)
    # ------------------------------------------------------------
    case push p
        echo "🌐 cz push"
        chezmoi git -- push
        echo "🚀 Pushed"
        return 0

    # ------------------------------------------------------------
    # FULL (full pipeline)
    # ------------------------------------------------------------
    case full f
        echo "🛠️ cz full"

        cz update
        cz add
        cz record "Full sync dotfiles"

        echo "🏆 Full sync complete"
        return 0

    # ------------------------------------------------------------
    # UNKNOWN
    # ------------------------------------------------------------
    case '*'
        echo "Unknown command: cz $cmd"
        echo "Run: cz help"
        return 1
    end
end
