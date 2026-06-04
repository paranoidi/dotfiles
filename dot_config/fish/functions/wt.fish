function wt --description "🌳 Git work-tree task manager"
    # ── Configuration via env vars ────────────────────────────────────
    # WT_ROOT          - project root (default: auto-detect from git)
    # WT_WORKTREE_DIR  - worktree directory name (default: ".worktrees")

    set -l cmd $argv[1]
    set -e argv[1]

    # ── Find project root ─────────────────────────────────────────────
    # Use git-common-dir (not --show-toplevel): inside a linked worktree,
    # show-toplevel is the worktree path and would break .worktrees resolution; dirname of common-dir is main repo
    set -l root_dir $WT_ROOT
    if test -z "$root_dir"
        set -l git_common (git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
        if test -n "$git_common"
            set root_dir (dirname $git_common)
        else
            set root_dir (git rev-parse --show-toplevel 2>/dev/null)
        end
    end
    if test -z "$root_dir"
        echo "🚫 not in a git repository (set WT_ROOT to override)" >&2
        return 1
    end

    set -l worktree_dir "$root_dir/$WT_WORKTREE_DIR"
    if test -z "$WT_WORKTREE_DIR"
        set worktree_dir "$root_dir/.worktrees"
    end

    # Shorthand: wt <name> [base-branch] → start
    if begin
            test -n "$cmd"
            and not contains -- $cmd start s list ls status done d kill open reattach clean help
        end
        __wt_start $root_dir $worktree_dir $cmd $argv
        return
    end

    switch "$cmd"
        case start s
            __wt_start $root_dir $worktree_dir $argv
        case list ls
            git -C $root_dir worktree list --verbose
        case status
            __wt_status $root_dir $worktree_dir
        case done d
            set -l tn $argv[1]
            if test -n "$tn"
                __wt_done $root_dir $worktree_dir $tn
            else
                set -l inferred (__wt_infer_name $worktree_dir)
                if test -n "$inferred"
                    __wt_done $root_dir $worktree_dir $inferred
                else
                    __wt_done_interactive $root_dir $worktree_dir
                end
            end
        case kill
            if test -n "$argv[1]"
                __wt_kill $root_dir $worktree_dir $argv[1]
            else
                __wt_kill_interactive $root_dir $worktree_dir
            end
        case open reattach
            set -l tn $argv[1]
            test -z "$tn"; and set tn (__wt_infer_name $worktree_dir)
            __wt_open $root_dir $worktree_dir $tn
        case clean
            __wt_clean $root_dir $worktree_dir
        case '' help
            echo "Usage: wt <name> [base-branch] | wt <command> [args]"
            echo ""
            echo "  <name> [branch]            Create task worktree (same as start); branch defaults to current branch"
            echo ""
            echo "Commands:"
            echo "  start | s <name> [branch]  Create worktree from branch (default: current branch)"
            echo "  list | ls                  List git worktrees"
            echo "  status                     Branch, dirty files, and sync vs origin for each task worktree"
            echo "  done | d [name]            Merge into main and remove task worktree; no name outside worktree → fzf (single)"
            echo "  kill [name]                Abandon worktree(s); no name + fzf → multi-select interactively"
            echo "  open [name]                cd into existing task worktree"
            echo "  clean                      Remove ALL worktrees (interactive)"
            echo ""
            echo "Configuration (set before calling wt):"
            echo "  set -gx WT_ROOT         Project root (default: auto-detect)"
            echo "  set -gx WT_WORKTREE_DIR Worktree dir (default: .worktrees)"
        case '*'
            echo "🚫 unknown command '$cmd'" >&2
            return 1
    end
end

# Infer task name from cwd when inside $worktree_dir/<name>[/...]
function __wt_infer_name -a worktree_dir
    set -l wt (realpath $worktree_dir 2>/dev/null)
    test -n "$wt"; or return
    set -l cwd (realpath $PWD 2>/dev/null)
    test -n "$cwd"; or return
    set -l prefix "$wt/"
    string match -q "$prefix*" "$cwd"; or return
    set -l rest (string replace "$prefix" "" "$cwd")
    test -n "$rest"; or return
    echo (string split / $rest)[1]
end

# ── wt start <name> [base-branch] ─────────────────────────────────────
function __wt_start -a root_dir worktree_dir args
    set -l name $args[1]
    set -l base_branch $args[2]
    if test -z "$base_branch"
        set base_branch (git -C $root_dir rev-parse --abbrev-ref HEAD 2>/dev/null)
        test -z "$base_branch"; and set base_branch main
    end

    if test -z "$name"
        echo "usage: wt start <name> [base-branch]" >&2
        return 1
    end

    set -l wtdir "$worktree_dir/$name"
    set -l task_branch "task/$name"

    mkdir -p $worktree_dir

    if test -d "$wtdir"
        echo "🚫 worktree '$name' already exists at $wtdir" >&2
        return 1
    end

    # Create task branch from base branch if it doesn't exist
    if not git -C $root_dir rev-parse --verify "$task_branch" &>/dev/null
        echo "creating branch '$task_branch' from '$base_branch'..."
        git -C $root_dir fetch origin "$base_branch" 2>/dev/null; or true
        git -C $root_dir branch "$task_branch" "origin/$base_branch" 2>/dev/null
        or git -C $root_dir branch "$task_branch" "$base_branch"
    else
        echo "branch '$task_branch' already exists"
    end

    echo "💾 Creating worktree '$name'..."
    git -C $root_dir worktree add "$wtdir" "$task_branch"

    echo "🏆 Worktree created: $name (branch: $task_branch)"
    cd $wtdir
    set -l agent (set -q DEFAULT_AGENT; and echo $DEFAULT_AGENT; or echo pi)
    $agent
end

# ── wt status ─────────────────────────────────────────────────────────
function __wt_status -a root_dir worktree_dir
    echo "=== Task worktrees ==="
    for wt in $worktree_dir/*/
        test -d "$wt"; or continue
        set -l name (basename $wt)
        set -l branch (git -C $wt rev-parse --abbrev-ref HEAD 2>/dev/null; or echo "?")
        set -l dirty (git -C $wt status --porcelain 2>/dev/null | wc -l)

        # Compare to: configured upstream, else origin/<branch> when that ref exists,
        # else an integration ref (topic never pushed → origin/<branch> missing).
        set -l cmp ''
        set -l cmp_human ''
        set -l cmp_is_topic 0
        if git -C $wt rev-parse --verify '@{upstream}' &>/dev/null
            set cmp '@{upstream}'
            set cmp_human (git -C $wt rev-parse --abbrev-ref '@{upstream}')
            set cmp_is_topic 1
        else if git -C $wt rev-parse --verify "origin/$branch" &>/dev/null
            set cmp "origin/$branch"
            set cmp_human "origin/$branch"
            set cmp_is_topic 1
        else
            for cand in origin/main origin/master main master
                if git -C $wt rev-parse --verify $cand &>/dev/null
                    set cmp $cand
                    set cmp_human $cand
                    break
                end
            end
        end

        echo "  $name"
        echo "    branch:  $branch"
        echo "    dirty:   $dirty file(s)"
        if test -z "$cmp"
            echo "    origin:  could not compare (no upstream, no origin/$branch, no main/master ref)"
        else
            set -l ahead (git -C $wt rev-list --count "$cmp"..HEAD 2>/dev/null; or echo "?")
            set -l behind (git -C $wt rev-list --count HEAD.."$cmp" 2>/dev/null; or echo "?")
            if test "$ahead" = "?" -o "$behind" = "?"
                echo "    origin:  could not compare to $cmp_human"
            else
                echo "    commits: $ahead ahead, $behind behind (vs $cmp_human)"
                if test "$cmp_is_topic" -eq 0
                    echo "    origin:  no origin/$branch yet — git push -u origin $branch"
                end
            end
        end
        echo ""
    end
end

# ── wt done <name> (alias: d) ─────────────────────────────────────────
function __wt_done -a root_dir worktree_dir name
    set -l wtdir "$worktree_dir/$name"

    if test -z "$name"
        echo "usage: wt done [name]  (alias: d; name defaults when cwd is under .worktrees/<name>)" >&2
        return 1
    end
    if not test -d "$wtdir"
        echo "🚫 worktree '$name' not found at $wtdir" >&2
        return 1
    end

    echo "=== Finishing task: $name ==="

    # 1. Merge from primary repo ($root_dir). `main` is often checked out only there; a task
    #    worktree cannot `checkout main` in that case, which used to yield a false “Already up to date”.
    echo "--- Merging ---"
    set -l task_branch "task/$name"
    git -C $root_dir fetch origin main 2>/dev/null; or echo "  (no remote / fetch skipped)"
    git -C $root_dir checkout main
    if test $status -ne 0
        echo "🚫 could not checkout main in $root_dir (resolve repo state and retry)" >&2
        return 1
    end
    git -C $root_dir pull origin main 2>/dev/null; or echo "  (no remote / pull skipped)"
    git -C $root_dir merge $task_branch --no-edit
    if test $status -ne 0
        echo "🚫 merge $task_branch into main failed — fix conflicts in $root_dir, then run: wt done $name" >&2
        return 1
    end
    git -C $root_dir push origin main 2>/dev/null; or echo "  (no remote / push skipped)"
    echo "  merged $task_branch -> main"

    # 2. Cleanup — remove worktree first so task_branch is no longer checked out, then delete branch ref
    echo "--- Removing worktree ---"
    git -C $root_dir worktree remove $wtdir 2>/dev/null
    or git -C $root_dir worktree remove --force $wtdir 2>/dev/null
    git -C $root_dir worktree prune
    git -C $root_dir branch -d $task_branch 2>/dev/null
    or echo "🚫 could not delete local branch $task_branch" >&2
    git -C $root_dir push origin --delete $task_branch 2>/dev/null; or true

    echo ""
    echo "🏆 Done: $name -- merged to main"
end

# ── wt done (no args, not under worktree: fzf single-select) ────────
function __wt_done_interactive -a root_dir worktree_dir
    if not type -q fzf
        echo "🚫 wt done with no task name (outside a task worktree) requires fzf (install: https://github.com/junegunn/fzf)" >&2
        return 1
    end

    set -l names
    for entry in $worktree_dir/*/
        test -d "$entry"; or continue
        set -l n (basename $entry)
        test -n "$n"; or continue
        set names $names $n
    end
    if test (count $names) -eq 0
        echo "🚫 no task worktrees under $worktree_dir" >&2
        return 1
    end

    set -l picked (printf '%s\n' $names | sort | fzf \
        --header='Task to finish — pick one (enter confirms, esc cancels):' \
        --prompt='done> ')
    if test $status -ne 0
        return 1
    end
    test -n "$picked"; or return 1
    __wt_done $root_dir $worktree_dir $picked
end

# ── wt kill (no args, fzf multi-select) ───────────────────────────────
function __wt_kill_interactive -a root_dir worktree_dir
    if not type -q fzf
        echo "🚫 wt kill with no task name requires fzf (install: https://github.com/junegunn/fzf)" >&2
        return 1
    end

    set -l names
    for entry in $worktree_dir/*/
        test -d "$entry"; or continue
        set -l n (basename $entry)
        test -n "$n"; or continue
        set names $names $n
    end
    if test (count $names) -eq 0
        echo "🚫 no task worktrees under $worktree_dir" >&2
        return 1
    end

    set -l picked (printf '%s\n' $names | sort | fzf --multi \
        --header='Tasks to abandon — tab toggles selection, enter confirms (esc cancels):' \
        --prompt='kill> ')
    if test $status -ne 0
        return 1
    end
    for n in $picked
        test -n "$n"; or continue
        __wt_kill $root_dir $worktree_dir $n
    end
end

# ── wt kill <name> ────────────────────────────────────────────────────
function __wt_kill -a root_dir worktree_dir name
    set -l wtdir "$worktree_dir/$name"

    if test -z "$name"
        echo "usage: wt kill [name]  (no name: multi-select via fzf if installed)" >&2
        return 1
    end
    if not test -d "$wtdir"
        echo "🚫 worktree '$name' not found at $wtdir" >&2
        return 1
    end

    cd $root_dir
    or begin
        echo "🚫 could not cd to project root $root_dir" >&2
        return 1
    end

    echo "Abandoning task: $name"
    git -C $root_dir worktree remove $wtdir 2>/dev/null
    or begin
        git -C $root_dir worktree remove --force $wtdir 2>/dev/null; or true
        rm -rf $wtdir
    end
    git -C $root_dir worktree prune
    git -C $root_dir branch -D "task/$name" 2>/dev/null; or true
    git -C $root_dir push origin --delete "task/$name" 2>/dev/null; or true
    echo "☠️ Abandoned: $name"
end

# ── wt open <name> ────────────────────────────────────────────────────
function __wt_open -a root_dir worktree_dir name
    set -l wtdir "$worktree_dir/$name"

    if test -z "$name"
        echo "usage: wt open [name]  (name defaults when cwd is under .worktrees/<name>)" >&2
        return 1
    end
    if not test -d "$wtdir"
        echo "🚫 worktree '$name' not found at $wtdir" >&2
        return 1
    end

    cd $wtdir
    echo "🏆 Now in worktree: $name"
end

# ── wt clean (interactive) ─────────────────────────────────────────────
function __wt_clean -a root_dir worktree_dir
    echo "WARNING: This will remove ALL worktrees in $worktree_dir/"
    echo "Unmerged changes will be lost."
    echo ""
    git -C $root_dir worktree list --verbose
    echo ""
    read -p 'echo "Type yes to proceed: "' confirm
    test "$confirm" = "yes"; or begin
        echo "Aborted."
        return 1
    end

    for wt in $worktree_dir/*/
        test -d "$wt"; or continue
        set -l name (basename $wt)
        echo "Removing $name..."
        git -C $root_dir worktree remove $wt 2>/dev/null
        or begin
            git -C $root_dir worktree remove --force $wt 2>/dev/null; or true
            rm -rf $wt
        end
    end

    echo "🏆 All worktrees removed"
end
