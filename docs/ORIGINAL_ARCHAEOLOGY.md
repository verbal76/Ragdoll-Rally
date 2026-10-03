# Ragdoll Rally: Original — archaeology record (2026-10-03)

**Result: the historical Original source is NOT recoverable from this repository or from anything reachable by the tooling used. Original implementation work is STOPPED (no replacement game was written).**

Searched (all with negative results for game source):
- All refs: `ccr-7c0d7291-e3d5o1`, `main`, `verbal76-patch-1`, `claude/launch-api36-modernization`; `refs/pull/1/head`, `refs/pull/2/head`, `refs/pull/2/merge`; all tags (`launch-poc-b1..b6`, `launch-ota-*`) via `git ls-remote` and the GitHub API.
- Entire reachable history (12 commits): the only non-Launch content ever committed is `README.md`, `docs/PRODUCT_HISTORY.md`, `docs/RECOVERY_MANIFEST.md` and the two Kenney zips (`kenney_blocky-characters_20.zip`, `kenney_retro-fantasy-kit.zip`; their only HTML is Kenney's `Overview.html`).
- Pickaxe (`git log --all -S`) for `Matter`, `matter-js`, `Capacitor`, `capacitor`, `slingshot`, `Bodies`: hits only in the two history docs and in docs written in this project's Launch work.
- `git rev-list --all --objects` for html/js/css/apk/json blobs: none besides Launch files.
- Unreachable objects in the clone (`git fsck`): two stash artifacts from this session, no game files.
- Pull requests: #1 (upload of a Kenney zip), #2 (Launch). No other PRs/branches. GitHub code search for `Matter.Engine` in the owner's repositories: 0 results. Actions history: only this project's Launch workflows. Releases: only `launch-poc-*` and `launch-ota-*`.
- Web search for a public CodePen/GitHub copy of "Ragdoll Rally": nothing matching.

What survives is only the textual record in `docs/PRODUCT_HISTORY.md` and `docs/RECOVERY_MANIFEST.md` (Matter.js/CodePen origin; web/index.html, web/style.css, web/game.js, optional web/lib/matter.min.js; Capacitor intent; feature list). The manifest itself states the verbatim code was never recovered.

What is needed to unblock Original (owner action): the original CodePen URL/export, any Capacitor project folder, a historical APK, or the 2025-09-01/02 source pasted into the repository. With real source in hand, modernization can proceed as specified (keep Matter.js, Capacitor, API 36, distinct package `com.hotatticgames.ragdollrally.original`, separate workflow).
Rule kept: no Original gameplay is reconstructed from memory or invented without explicit owner authorization.
