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

        # Chezmoi uses " R" for run-on-apply scripts; avoid confusion with Removed.
        if string match -rq '^ R' -- "$line"
            echo (string replace -r '^ R' '🚀' -- "$line")
        else
            echo "$line"
        end
    end
end

function __cz_source_dir
    chezmoi execute-template '{{ .chezmoi.sourceDir }}'
end

function __cz_git_repo_summary
    set -l sd (__cz_source_dir)

    if not test -d "$sd"
        echo "🚫 chezmoi source directory not found: $sd"
        return 1
    end

    if not git -C "$sd" rev-parse --is-inside-work-tree >/dev/null 2>&1
        echo "🚫 Not a git repository: $sd"
        return 1
    end

    set -l staged_paths (git -C "$sd" diff --cached --name-only | string trim | string match -rv '^$')
    set -l modified_paths (git -C "$sd" diff --name-only | string trim | string match -rv '^$')
    set -l lines

    set -l staged_count (count $staged_paths)
    if test $staged_count -gt 0
        set -a lines "   staged:   $staged_count file(s)"
    end

    set -l modified_count (count $modified_paths)
    if test $modified_count -gt 0
        set -a lines "   modified: $modified_count file(s) (unstaged)"
    end

    if git -C "$sd" rev-parse --abbrev-ref @{upstream} >/dev/null 2>&1
        set -l unpushed (git -C "$sd" rev-list --count @{upstream}..HEAD 2>/dev/null)
        if test "$unpushed" -gt 0
            set -a lines "   unpushed: $unpushed commit(s)"
        end
    end

    if test (count $lines) -eq 0
        return 2
    end

    echo "🔀 Chezmoi git"
    for line in $lines
        echo $line
    end

    return 0
end

function __cz_rel_path_in_head --argument-names sd rel_path
    git -C "$sd" cat-file -e "HEAD:$rel_path" 2>/dev/null
end

function __cz_clean_resolve_target --argument-names sd rel_path
    set -l D (git -C "$sd" log --diff-filter=D -1 --pretty=%H -- -- "$rel_path" 2>/dev/null)
    test -n "$D"; or return 1
    if not git -C "$sd" rev-parse --verify -q "$D^" >/dev/null 2>&1
        return 1
    end
    set -l parent (git -C "$sd" rev-parse "$D^")

    set -l item_tmp (mktemp -d)
    set -l dst "$item_tmp/$rel_path"
    mkdir -p (path dirname "$dst"); or begin
        rm -rf "$item_tmp"
        return 1
    end

    if not git -C "$sd" show "$parent:$rel_path" >"$dst" 2>/dev/null
        rm -rf "$item_tmp"
        return 1
    end

    set -l target (chezmoi target-path -S "$item_tmp" -D "$HOME" "$dst" 2>/dev/null)
    set -l st $status
    rm -rf "$item_tmp"
    if test $st -ne 0; or test -z "$target"
        return 1
    end
    printf '%s' "$target"
end

function __cz_clean_decline_file --argument-names sd
    printf '%s' "$sd/.chezmoi/cz_clean_declines"
end

function __cz_clean_commit_declines
    set -l sd $argv[1]
    set -l pending $argv[2..-1]

    if test (count $pending) -eq 0
        return 0
    end

    set -l decline_f (__cz_clean_decline_file "$sd")
    set -l existing
    if test -f "$decline_f"
        set existing (string trim <$decline_f | string match -rv '^$')
    end

    set -l merged (printf '%s\n' $existing $pending | string trim | string match -rv '^$' | sort -u)

    mkdir -p (path dirname "$decline_f")
    printf '%s\n' $merged >"$decline_f"

    if not chezmoi git -- add .chezmoi/cz_clean_declines
        echo "🚫 chezmoi git add failed for .chezmoi/cz_clean_declines"
        return 1
    end

    if chezmoi git -- diff --staged --quiet
        echo "ℹ️ Decline manifest unchanged in git (paths already recorded)"
        return 0
    end

    if chezmoi git -- commit -m "cz clean: record keep-local declines"
        echo "🏆 Recorded keep-local declines in chezmoi git"
        return 0
    end

    echo "🚫 chezmoi git commit failed; fix or run cz record"
    return 1
end

function __cz_clean
    set -l sd (__cz_source_dir)

    if not test -d "$sd"
        echo "🚫 chezmoi source directory not found: $sd"
        return 1
    end

    if not git -C "$sd" rev-parse --is-inside-work-tree >/dev/null 2>&1
        echo "🚫 Not a git repository: $sd"
        return 1
    end

    set -l rel_paths (
        git -C "$sd" log --all --diff-filter=D --name-only --pretty=format: |
        string trim |
        string match -rv '^$' |
        sort -u
    )

    if test (count $rel_paths) -eq 0
        echo "ℹ️ No deleted source paths in git history"
        return 0
    end

    set -l decline_f (__cz_clean_decline_file "$sd")
    set -l declined_paths
    if test -f "$decline_f"
        set declined_paths (string trim <$decline_f | string match -rv '^$')
    end

    set -l prompted 0
    set -l removed 0
    set -l aborted 0
    set -l pending_declines

    for rel_path in $rel_paths
        if __cz_rel_path_in_head "$sd" "$rel_path"
            continue
        end

        if contains -- "$rel_path" $declined_paths
            echo "⏭️ $rel_path (keep-local, recorded earlier)"
            continue
        end

        set -l target (__cz_clean_resolve_target "$sd" "$rel_path")
        if test $status -ne 0; or test -z "$target"
            continue
        end

        if not test -e "$target"
            continue
        end

        if chezmoi source-path "$target" >/dev/null 2>&1
            continue
        end

        set -l D (git -C "$sd" log --diff-filter=D -1 --pretty=%H -- -- "$rel_path" 2>/dev/null)
        set -l subj (git -C "$sd" log -1 --pretty=%s "$D" 2>/dev/null)

        echo ""
        echo "Removed from repo : $rel_path"
        echo "Deleting commit   : $subj"
        echo "Still on disk     : $target"

        read -P "Remove this path? [y/N/q] " ans

        if string match -q -i q -- "$ans"
            set aborted 1
            echo "Stopped."
            break
        end

        if string match -q -i y -- "$ans"
            if test -d "$target"
                rm -rf "$target"
            else
                rm -f "$target"
            end
            echo "💀 Removed"
            set prompted (math $prompted + 1)
            set removed (math $removed + 1)
        else
            set prompted (math $prompted + 1)
            read -P "Record this keep-local choice in chezmoi git? [y/N] " record_one
            if string match -q -i y -- "$record_one"
                set -a pending_declines $rel_path
            end
        end
    end

    __cz_clean_commit_declines "$sd" $pending_declines
    set -l commit_st $status

    echo ""
    if test $aborted -eq 1
        echo "🏆 cz clean stopped ($removed removed, "(math $prompted - $removed)" skipped before quit)"
        test $commit_st -eq 0; or return 1
        return 0
    end

    if test $prompted -eq 0
        echo "ℹ️ No leftover files on disk for historical source deletes (or all still managed / back in HEAD)"
        test $commit_st -eq 0; or return 1
        return 0
    end

    echo "🏆 cz clean finished ($removed removed, "(math $prompted - $removed)" skipped)"
    test $commit_st -eq 0; or return 1
    return 0
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
        echo -e "  cz \e[1mc\e[0mlean        → Offer to remove deleted files (git deletes; renames not covered)"
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
            echo "⚓️ Hook: $hook"
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
        __cz_git_repo_summary
        switch $status
        case 0
            echo ""
        case 2
            # nothing noteworthy in chezmoi git
        case 1
            return 1
        case '*'
            return $status
        end
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
    # CLEAN (HOME leftovers after source file deleted in git)
    # ------------------------------------------------------------
    case clean c
        echo "🧹 cz clean — stale targets from git delete history"
        __cz_clean
        return $status

    # ------------------------------------------------------------
    # UNKNOWN
    # ------------------------------------------------------------
    case '*'
        echo "Unknown command: cz $cmd"
        echo "Run: cz help"
        return 1
    end
end
