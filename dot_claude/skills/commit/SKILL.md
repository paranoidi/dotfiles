---
name: commit
description: Create atomic git commits using Conventional Commits. Use this skill when the user invokes "/commit", says "commit this", "make a commit", "commit my changes", "split into commits", or otherwise asks to stage and commit pending git changes. Delegates the actual commit work to a Haiku or Sonnet subagent depending on diff complexity to keep the main loop fast and cheap.
version: 1.0.0
---

# commit

Create atomic Conventional Commits for the pending changes in the working tree. Delegate the work to a subagent — Haiku for simple diffs, Sonnet for complex ones — to keep the main loop context clean and minimize cost.

## Step 1: Triage the diff

Before spawning the subagent, run these in parallel from the working directory to size the change:

```bash
git status --short
git --no-pager diff HEAD --stat
```

Use the output to pick the model:

- **Haiku** (`claude-haiku-4-5-20251001`) — pick when ALL of:
  - ≤ 5 files changed
  - ≤ 150 lines changed total (sum of insertions + deletions from `--stat`)
  - Changes look like a single logical concern (e.g. one feature dir, one bugfix, docs-only, dep bump)
- **Sonnet** (`claude-sonnet-4-6`) — pick when ANY of:
  - > 5 files or > 150 lines changed
  - Changes span unrelated areas (likely needs splitting into multiple commits)
  - Mixed types (feat + refactor + test in unrelated areas)
  - Anything ambiguous about scope, type, or breaking-change status

When in doubt, prefer Sonnet. The cost difference is small compared to a bad commit history.

## Step 2: Spawn the subagent

Spawn one Agent via the Agent tool with:

- `subagent_type`: `general-purpose`
- `model`: chosen per Step 1 (`haiku` or `sonnet`)
- `description`: `Atomic conventional commits`
- `prompt`: the full instructions from [Subagent prompt](#subagent-prompt) below, verbatim.

Do not run `git commit` yourself in the main loop. The whole point is to offload.

## Step 3: Report back

After the subagent returns, briefly summarize to the user: number of commits created and their subject lines. Do not re-describe each diff.

---

## Subagent prompt

Paste this verbatim into the spawned agent's `prompt`:

```
Create atomic git commits for the pending changes in the current working directory, following Conventional Commits. You are running non-interactively from a detached session — never open an editor or pager, never run `git push`, never use `-i` flags.

# Process

1. Inspect changes:
   - `git status`
   - `git --no-pager diff HEAD`
2. Decide: one commit or multiple? Split when the diff mixes unrelated concerns, types (feat + fix + refactor + docs + test + chore), or is large enough that smaller commits would be easier to review. If a single file would belong to two logical commits, pick one — do not try to partial-stage hunks within a file.
3. For each commit:
   - Stage only the relevant paths with `git add <paths>` (never `git add .` unless it truly is one commit covering everything).
   - Verify with `git --no-pager diff --cached`.
   - Commit with `git commit -m "<subject>"` (add `-m "<body>"` for a body when needed).
4. After all commits: run `git pull --rebase`. If conflicts occur, resolve and continue with `git rebase --continue`. If you cannot resolve cleanly, stop and report.
5. Return: list of commits created (hash + subject), and anything notable (skipped files, rebase result).

# Subject line

- Format: `<type>[optional scope]: <description>`
- Breaking change: `<type>[scope]!: <description>` and/or `BREAKING CHANGE:` footer
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`, `ci`, `build`, `revert`
- Scope: optional, parenthesized, identifies module/area (`auth`, `api`, `parser`, `db`, ...)
- Imperative present tense ("add", "fix" — not "added", "fixes")
- ≤ 72 chars, no trailing period

# Type rules

- `feat` / `fix`: user-facing change. Internal tooling is `chore`, not `feat`.
- `docs`: documentation only
- `refactor`: no behavior change
- `test`: tests only
- `perf`: performance
- `ci` / `build`: pipeline / build system
- `revert`: reverts a prior commit

# Body (optional)

Use when the "why" is non-obvious. Blank line after subject, wrap at 72 chars, explain motivation/context — not what the diff already shows.

# Anti-patterns to avoid

- Mixing unrelated changes
- Vague messages ("fix: fix bug", "chore: update stuff")
- Past tense, trailing period, missing type, > 72 chars
- `feat` for internal tooling

# Output

Return only: the commits made (hash + subject, one per line), and any warnings. No prose summary.
```

## Why this design

- **Model split** — most commits are mechanical: read a small diff, pick a type, write a subject. Haiku handles that fast and cheap. Sonnet kicks in only when splitting/judgment is needed.
- **Triage in main loop** — model choice depends on diff size, which is a 2-command check. Doing it before spawning avoids paying Sonnet rates for trivial commits.
- **Subagent isolation** — commit work involves many `git` calls and diff output. Keeping that out of the main loop preserves context for the actual development task the user came in for.
