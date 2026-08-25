---
name: ship-pr-review-loop
description: "Ship a completed change: branch, validate, open/update PR, watch CI with polling, request Copilot review, fix feedback, then squash-merge and delete the branch. Use when the user says /ship-pr-review-loop, wants a PR review loop, or asks to squash-merge after Copilot is clean."
disable-model-invocation: true
---

# Ship PR, CI, Copilot review, squash-merge

User-invoked delivery loop for this repo. Prefer repo conventions over generic assumptions.

## Goal

Drive a finished implementation to merge:

1. branch + commit (if needed)
2. local validation
3. draft PR → CI green on latest head
4. ready for review + Copilot reviewer assigned
5. address feedback until clean
6. squash-merge and delete the branch

## Polling contract

Do **not** burn the turn on busy-wait loops. Between polls:

- Prefer `gh run watch --exit-status` for Actions once a run id is known.
- Otherwise poll with `gh` every **30–60s**, max **30 minutes** per wait phase.
- After each poll, if still waiting, emit a one-line status and continue.
- Always compare against the **latest PR head SHA**, never an older green commit.

## Workflow

### 1. Baseline

```bash
git status -sb
git branch --show-current
git remote -v
git log --oneline -5
gh repo view --json nameWithOwner,defaultBranchRef
```

- Default base: `main`.
- If work is on `main` with a dirty tree, create `feat/<short-slug>` first.
- Never commit secrets.

### 2. Local validation (narrowest meaningful set)

From the workspace root, for packages touched by the diff:

```bash
flutter pub get
# For each changed Dart package with tests:
(cd packages/<pkg> && flutter test)
# iOS route policy when Swift policy/tests change:
(cd packages/flutter_ai_communications_ios/ios/flutter_ai_communications_ios/IosRoutePolicy && swift test)
```

Do not open a PR from obviously broken local state.

### 3. Commit and push

- Conventional commits (`feat`, `fix`, `ci`, `docs`, …).
- Push with `-u` on first push.

### 4. Open or update the PR

```bash
gh pr view --json number,url,isDraft,headRefName,baseRefName,statusCheckRollup,reviewRequests,reviews,commits
# create if missing
gh pr create --draft --base main --title "…" --body "…"
```

PR body must cover: summary, validation, device receipts if any, limitations.

### 5. Watch CI

```bash
gh pr checks <n>
gh run list --branch <branch> --limit 5
gh run watch <run-id> --exit-status
```

On failure: inspect logs, fix, push, watch the **new** head. Prefer rerunning only failed jobs.

### 6. Ready + Copilot review

When latest head is green:

```bash
gh pr ready <n>
gh pr view <n> --json reviewRequests,reviews
# only if Copilot is not already requested:
gh pr edit <n> --add-reviewer copilot-pull-request-reviewer[bot]
```

Then poll reviews/comments until Copilot finishes or actionable threads appear.

### 7. Review loop

For each cycle:

1. Collect review bodies + unresolved threads (`gh api` / `gh pr view`).
2. Fix only actionable items in small commits.
3. Re-run the narrowest local checks.
4. Push and watch CI on the new head.
5. Ensure Copilot is still assigned; wait for the next review.
6. Repeat until no unresolved actionable comments and CI is green.

### 8. Squash-merge and delete branch

When review is clean and CI is green on the latest head:

```bash
gh pr merge <n> --squash --delete-branch
git checkout main
git pull --ff-only origin main
```

If the local feature branch remains, delete it.

## Completion criteria

- working tree clean
- PR squash-merged
- branch deleted on remote (and local if present)
- user gets: PR URL, final CI status, review status, merge SHA

## Stop and ask only for

- missing credentials / permissions
- ambiguous release/version intent
- conflicting product judgment in review

Do not stop for another obvious next step inside this loop.
