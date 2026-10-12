# Build pipeline: how GitHub finds and runs the Coordinated build

## Why the first dispatch returned 404 (verified 2026-10-12)
- `main` has no `.github` directory at all (README, logo, docs, the two Kenney zips). The workflows shown in the Actions list (`android.yml`, `launch-ota.yml`,
  `release-retrofit.yml`, `checks.yml`) were registered **because they ran** from the authoritative branch; GitHub only knows a workflow file after an event has
  started a run of it. `build.yml` was dispatch-only, so it never ran and was never registered: `GET /actions/workflows/build.yml` -> 404, dispatch -> 404.
- Not a permissions problem: dispatching `checks.yml` on the same ref answers `422 Workflow does not have 'workflow_dispatch' trigger` (the API resolved the file
  on the branch and read its triggers); with the same token. Not the file name or the ref either.
- So `main` does NOT have to change. The default branch is only special for the web UI "Run workflow" button; the REST/`gh` dispatch takes a `ref`.
## Repair (branch only)
`build.yml` additionally triggers on `pull_request` limited to edits of `.github/workflows/build.yml`, and that event runs one `echo` job (`registration`); every
other job is gated on `workflow_dispatch`. The first push that touches build.yml on the PR registers the workflow; nothing is built, tagged, released or published.
Builds still start only by dispatch (`ref` = the authoritative branch, `source_sha` = the exact commit).
## Fallback if registration alone does not enable dispatch
A stub on `main` would have to be a dispatcher: `main` is not allowed to carry gameplay code or a copy of the build logic. GitHub facts that constrain it:
a reusable-workflow `uses:` ref must be a literal (it cannot take the requested SHA), the callee sees the CALLER's `github` context (so `ref_name` would be `main`),
and the callee's permissions are capped by the caller. A minimal stub = `workflow_dispatch` inputs + one job
`uses: verbal76/Ragdoll-Rally/.github/workflows/build.yml@claude/launch-gameplay-pivot` with `permissions: contents: write` and the four inputs passed through
(build.yml would also need `workflow_call`, and its plan job would check out `source_sha` and drop the `ref_name` check). Needs explicit owner approval before touching `main`.
## Android versionCode
Fixed in the same pass: `versionCode = 1000 + build number`. The first `build.yml` draft used `github.run_number` of the NEW workflow, which would have started at 1 and
produced an APK Android refuses to install over v14-v18 (versionCode 27-31).
