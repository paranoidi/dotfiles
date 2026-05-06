function __cz_modified_files
    chezmoi status | awk '$1 ~ /^[ M]/ {print $2}'
end

function __cz_deleted_files
    chezmoi status | awk '$1 ~ /^D/ {print $2}'
end

function __cz_is_template_source --argument-names source_path
    string match -rq '(^|\.)tmpl($|\.)' -- "$source_path"
end

function __cz_status_without_template_sources
    chezmoi status | while read -l line
        set target_path (string trim -- "$line" | string replace -r '^\S+\s+' '')
        set source_path (chezmoi source-path "$HOME/$target_path" 2>/dev/null)

        if test $status -eq 0; and __cz_is_template_source "$source_path"
            continue
        end

        echo "$line"
    end
end

function __cz_import_changes
    set files (__cz_modified_files)

    if test (count $files) -eq 0
        echo "⚠️ No modified files"
        return 1
    end

    for f in $files
        set source_path (chezmoi source-path "$HOME/$f" 2>/dev/null)
        if test $status -ne 0
            echo "🚫 $f (could not resolve chezmoi source)"
            continue
        end

        if __cz_is_template_source "$source_path"
            echo "⏭️ $f (template source, skipped)"
            continue
        end

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
        echo -e "  cz \e[1mu\e[0mpdate       → Pull latest state + apply to \$HOME"
        echo -e "  cz \e[1ma\e[0mdd [file]   → Add all local changes into chezmoi (excl. templates) or given file"
        echo -e "  cz \e[1ms\e[0mtatus       → Show status diff"
        echo -e "  cz \e[1md\e[0miff         → Show detailed diff"
        echo -e "  cz \e[1mr\e[0mecord [msg] → Add all changes + git commit [message]"
        echo -e "  cz \e[1mp\e[0mush         → Push commits to remote"
        echo -e "  cz \e[1mf\e[0mull [msg]   → Full sync cycle [message]"
        echo -e "  cz \e[1mg\e[0mit          → cd into chezmoi source directory"
        return 0

    # ------------------------------------------------------------
    # UPDATE (repo → home)
    # ------------------------------------------------------------
    case update u
        echo "🌐 cz update"

        chezmoi update
        chezmoi apply

        for hook in (functions --all | string match '__cz_hook_update_*')
            echo "🔧 Hook: $hook"
            $hook
        end

        echo "🏆 Update complete"
        return 0

    # ------------------------------------------------------------
    # ADD (home → repo)
    # ------------------------------------------------------------
    case add a
        set file $argv[2]

        if test -n "$file"
            echo "🏠 cz add - Adding $file"
            chezmoi add "$file"
            echo "🏆 Add complete"
            return 0
        end

        echo "🏠 cz add - Importing local changes into chezmoi"

        __cz_import_changes

        # deletion handling
        set deleted (__cz_deleted_files)
        if test (count $deleted) -gt 0
            echo ""
            echo "⚠️ Deleted files detected:"
            for f in $deleted
                echo "   - $f"
            end

            read -P "❓ Remove these from chezmoi source as well? [y/N] " confirm
            if string match -q -i y -- "$confirm"
                for f in $deleted
                    echo "💀 $f"
                    chezmoi forget "$HOME/$f"
                end
            end
        end

        echo "🏆 Add complete"
        return 0

    # ------------------------------------------------------------
    # STATUS
    # ------------------------------------------------------------
    case status s
        echo "🏠 cz status"
        __cz_status_without_template_sources
        return 0

    # ------------------------------------------------------------
    # DIFF
    # ------------------------------------------------------------
    case diff d
        echo "🏠 cz diff"
        # Reverse diff direction so local additions appear as '+' (green).
        # Exclude run scripts (R entries) — they have no meaningful diff content.
        chezmoi diff --reverse --exclude=scripts
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
            echo "⚠️ Deleted files detected (not auto-handled in record):"
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
        echo "🏠 cz full"

        set msg (string join ' ' $argv[2..-1])
        if test -z "$msg"
            set msg "Full sync dotfiles"
        end

        cz update
        cz add
        cz record "$msg"

        echo "🏆 Full sync complete"
        return 0

    # ------------------------------------------------------------
    # GIT (cd into chezmoi source)
    # ------------------------------------------------------------
    case git g
        chezmoi cd
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
