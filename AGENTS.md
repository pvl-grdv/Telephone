# Repository Working Rules

These rules are authoritative for automated coding agents working on this repository.

## Repository scope

- Work only in `pvl-grdv/Telephone`.
- Treat `64characters/Telephone` as read-only upstream reference material.
- Never create, update, merge, close, comment on, or otherwise modify pull requests, issues, branches, releases, or settings in `64characters/Telephone` unless the user explicitly asks for that exact upstream action.
- Never open a pull request from this fork to `64characters/Telephone`.
- Do not suggest an upstream pull request as the normal completion path.

## Branch and integration workflow

- `master` is the permanent integration branch.
- For non-trivial changes, create a short-lived branch named `work/<short-topic>` from the current `master`.
- Keep the change focused. Do not create `v2`, `final`, `codex`, `personal`, `feature`, or `techdebt` variants for the same task.
- Push the work branch and use repository CI as the validation source.
- CI must pass both unit tests and the local app build before integrating.
- After CI is green, integrate the final result into `master` as one clean logical commit.
- Do not require or create a pull request for the normal solo-development workflow.
- After integration, the work branch is disposable and should be deleted when branch-deletion tooling is available. If deletion is unavailable, report that one manual cleanup step without reopening workflow discussion.

## Change policy

- Prefer small diffs and existing architecture.
- Do not rewrite Objective-C/AppKit to Swift/SwiftUI solely for modernization.
- Do not add architecture layers unless the task requires them.
- Preserve PJSIP/CoreAudio behavior unless the task explicitly targets that behavior.
- For macOS API availability, trust the actual project target and CI compiler over assumptions based on iOS APIs.
- If a speculative modernization fails platform availability or CI, revert it rather than adding compatibility complexity without a product need.

## Build and validation

- The project targets macOS and Apple silicon.
- Use the repository scripts rather than inventing a parallel build flow:
  - `./script/test.sh`
  - `./script/build.sh Debug`
  - `./script/build_and_run.sh`
- GitHub Actions runs CI on pushed branches. Treat a green CI run as the remote validation gate before updating `master`.
- When CI fails, inspect the failing job logs, fix the actual blocker on the work branch, and rerun through a new push.

## GitHub connector behavior

When GitHub connector access is available:

1. Read and modify only `pvl-grdv/Telephone` unless explicitly told otherwise.
2. Create `work/<topic>` from `master`.
3. Commit changes to that branch.
4. Verify CI.
5. Produce one clean final commit on top of the current `master`.
6. Fast-forward/update `master` to that commit.
7. Do not create a PR as part of this normal flow.

Repository settings and branch deletion may require manual GitHub UI actions if the connector does not expose them.
