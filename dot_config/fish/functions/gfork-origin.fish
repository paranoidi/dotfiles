function gfork-origin --description '🔀 Migrate GitHub origin to your fork'
    set --local use_https 0
    set --local dry_run 0

    for arg in $argv
        switch "$arg"
            case --https
                set use_https 1
            case --dry-run
                set dry_run 1
            case -h --help help
                echo "Usage: gfork-origin [--https] [--dry-run]"
                return 0
            case '*'
                echo "🚫 Error: unknown argument: $arg"
                echo "Usage: gfork-origin [--https] [--dry-run]"
                return 1
        end
    end

    if not command -q git
        echo "🚫 Error: git is required."
        return 1
    end

    if not command -q gh
        echo "🚫 Error: gh is required."
        return 1
    end

    set --local repo_root (git rev-parse --show-toplevel 2>/dev/null)

    if test -z "$repo_root"
        echo "🚫 Error: not inside a git repository."
        return 1
    end

    set --local origin_url (git -C "$repo_root" config --get remote.origin.url)

    if test -z "$origin_url"
        echo "🚫 Error: no remote.origin.url found."
        return 1
    end

    if not string match --quiet --regex '^(https?://github\.com/|git@github\.com:|ssh://git@github\.com/)' -- "$origin_url"
        echo "🚫 Error: origin is not a GitHub remote: $origin_url"
        return 1
    end

    set --local owner_repo "$origin_url"
    set owner_repo (string replace --regex '^https?://github\.com/' '' -- "$owner_repo")
    set owner_repo (string replace --regex '^git@github\.com:' '' -- "$owner_repo")
    set owner_repo (string replace --regex '^ssh://git@github\.com/' '' -- "$owner_repo")
    set owner_repo (string replace --regex '\.git$' '' -- "$owner_repo")
    set owner_repo (string replace --regex '/$' '' -- "$owner_repo")

    set --local owner_repo_parts (string split / -- "$owner_repo")

    if test (count $owner_repo_parts) -ne 2
        echo "🚫 Error: failed to parse owner/repo from origin URL: $origin_url"
        return 1
    end

    set --local owner $owner_repo_parts[1]
    set --local repo $owner_repo_parts[2]

    if test -z "$owner"; or test -z "$repo"
        echo "🚫 Error: failed to parse owner/repo from origin URL: $origin_url"
        return 1
    end

    set --local login (gh api user --jq .login 2>/dev/null)
    set --local gh_status $status

    if test $gh_status -ne 0
        echo "🚫 Error: failed to read authenticated GitHub user with gh."
        echo "Run: gh auth login"
        return 1
    end

    if test -z "$login"
        echo "🚫 Error: gh returned an empty GitHub login."
        return 1
    end

    set --local fork_repo "$login/$repo"
    set --local source_repo "$owner/$repo"

    if test "$owner" = "$login"
        echo "Origin is already set to your GitHub repo: $fork_repo"
        echo "Origin URL: $origin_url"
        return 0
    end

    set --local new_origin_url

    if test $use_https -eq 1
        set new_origin_url "https://github.com/$fork_repo.git"
    else
        set new_origin_url "git@github.com:$fork_repo.git"
    end

    if test -z "$new_origin_url"
        echo "🚫 Error: failed to build new origin URL."
        return 1
    end

    echo "🔀 Detected repo:"
    echo "  Source : $source_repo"
    echo "  Fork   : $fork_repo"
    echo "  Origin : $origin_url"
    echo "  New    : $new_origin_url"

    if test $dry_run -eq 1
        echo ""
        if git -C "$repo_root" remote get-url upstream >/dev/null 2>&1
            set --local upstream_url (git -C "$repo_root" remote get-url upstream)
            echo "Would leave existing upstream unchanged: $upstream_url"
        else
            echo "Would add upstream: $origin_url"
        end

        echo "Would ensure fork exists: $fork_repo"
        echo "Would set origin to: $new_origin_url"
        return 0
    end

    if gh repo view "$fork_repo" >/dev/null 2>&1
        echo "Fork already exists: $fork_repo"
    else
        echo "Creating fork: $source_repo → $fork_repo"
        gh repo fork "$source_repo" --clone=false --remote=false >/dev/null

        if test $status -ne 0
            echo "🚫 Error: failed to create fork: $source_repo"
            return 1
        end
    end

    if git -C "$repo_root" remote get-url upstream >/dev/null 2>&1
        set --local upstream_url (git -C "$repo_root" remote get-url upstream)
        echo "Upstream already exists, leaving unchanged: $upstream_url"
    else
        echo "Adding upstream: $origin_url"
        git -C "$repo_root" remote add upstream "$origin_url"

        if test $status -ne 0
            echo "🚫 Error: failed to add upstream remote."
            return 1
        end
    end

    echo "Updating origin from: $origin_url"
    echo "             to: $new_origin_url"
    git -C "$repo_root" remote set-url origin "$new_origin_url"

    if test $status -ne 0
        echo "🚫 Error: failed to update origin remote."
        return 1
    end

    echo "🏆 Done. Next push: git push -u origin HEAD"
end
