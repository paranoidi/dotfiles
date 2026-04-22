function __cz_modified_files
    chezmoi status | awk '$1 ~ /^[ M]/ {print $2}'
end

function __cz_deleted_files
    chezmoi status | awk '$1 ~ /^D/ {print $2}'
end

function __cz_import_changes
    set files (__cz_modified_files)

    if test (count $files) -eq 0
        echo "⚠️ No modified files"
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
        echo "cz - chezmoi workflow helper (fish)"
        echo ""
        echo "Commands:"
        echo "  cz update (u)    → pull latest state + apply to \$HOME"
        echo "  cz add (a)       → import local changes into chezmoi"
        echo "  cz status (s)    → show status diff"
        echo "  cz diff (d)      → show detailed diff"
        echo "  cz commit (c)    → import + git commit"
        echo "  cz push (p)      → push commits to remote"
        echo "  cz reconcile (r) → full sync cycle"
        return 0

    # ------------------------------------------------------------
    # UPDATE (repo → home)
    # ------------------------------------------------------------
    case update u
        echo "🌐 cz update"
        echo ""

        chezmoi update
        chezmoi apply

        echo "✅ Update complete"
        return 0

    # ------------------------------------------------------------
    # ADD (home → repo)
    # ------------------------------------------------------------
    case add a
        echo "🛠️ cz add - Importing local changes into chezmoi"
        echo ""

        __cz_import_changes

        # deletion handling
        set deleted (__cz_deleted_files)
        if test (count $deleted) -gt 0
            echo ""
            echo "⚠️ deleted files detected:"
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
        chezmoi diff
        return 0

    # ------------------------------------------------------------
    # COMMIT (safe + smart)
    # ------------------------------------------------------------
    case commit c
        echo "🛠️ cz commit"

        set modified (__cz_modified_files)
        if test (count $modified) -gt 0
            __cz_import_changes
        end

        set deleted (__cz_deleted_files)

        if test (count $deleted) -gt 0
            echo ""
            echo "⚠️ Deleted files detected (not auto-handled in commit):"
            for f in $deleted
                echo "  - $f"
            end
            echo "Run 'cz add' if you want to process deletions."
        end

        # check if anything actually staged in git
        if not chezmoi git -- status --porcelain | string length -q
            echo "ℹ️ Nothing to commit"
            return 0
        end

        set msg $argv[2]
        if test -z "$msg"
            set msg "Update dotfiles"
        end

        chezmoi git -- add -A
        chezmoi git -- commit -m "$msg"

        echo "💾 Committed"
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
    # RECONCILE (full pipeline)
    # ------------------------------------------------------------
    case reconcile r
        echo "🛠️ cz reconcile"
        echo ""

        cz update
        cz add
        cz commit "Reconcile dotfiles"

        echo "✅ Reconcile complete"
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
