---
name: orb-release
description: >
  Cut a production release of the telegram-notify orb — run the release
  preflight, tag vX.Y.Z, watch the publish job and verify the version in the
  CircleCI registry. Use when asked to "release", "tag", "publish vX.Y.Z",
  "ship the orb", or when the orb is missing a production version in the
  CircleCI Developer Hub registry.
allowed-tools: Bash, Read, Edit, Grep
---

# Orb release

Publishing is irreversible: **an orb version can never be republished or
deleted.** Everything below exists to make the tag correct the first time.

## 1. Prepare the release PR

On a branch, not on main:

- `CHANGELOG.md`: move the `## [Unreleased]` content under
  `## [X.Y.Z] - YYYY-MM-DD` and add the `[X.Y.Z]:` link reference at the bottom.
- Bump every documented pin to `@X.Y.Z`:
  `grep -rn 'kevnm67/telegram-notify@[0-9]' README.md wiki src/examples`
- `.github/SECURITY.md`: the supported-versions table names the new line.

Leave `.circleci/config.yml`'s `kevnm67/telegram-notify@dev:alpha` alone — that
self-reference is deliberate dogfooding, not a stale pin.

Merge the PR and wait for `main` to go green.

## 2. Preflight, then tag

```bash
git checkout main && git pull
scripts/dev/release-preflight.sh X.Y.Z
```

It checks branch, tree and sync state, that the tag is free, the CHANGELOG
section and link reference, every documented pin, the `main` commit status, and
`make lint test validate verify-diagrams`. **If it reports any FAIL, fix it and
re-run — never tag past a failure.** Only once it prints the tag command:

```bash
git tag vX.Y.Z && git push origin vX.Y.Z
```

## 3. Verify it actually published

```bash
circleci orb list kevnm67 | grep telegram-notify        # Version column populated
circleci orb source kevnm67/telegram-notify@X.Y.Z | head
gh release create vX.Y.Z --generate-notes
```

Then run `/live-test` if anything in `src/` changed since the last release.

## Gotchas

- **`circleci orb info` is not a command.** Use `circleci orb list <namespace>`
  or `circleci orb source <orb>@<version>`.
- A namespace can hold an orb with zero production versions: it appears in
  `circleci orb list` with an empty Version column but is **absent from the
  Developer Hub registry** until the first `X.Y.Z` publish. A missing registry
  listing almost always means no release has been tagged, not a broken
  namespace or a visibility setting.
- The tag pipeline reruns the integration jobs before `publish_production`
  (context `orb-publishing`). A red tag pipeline means nothing published — fix
  forward and tag the next patch; never delete and re-push the same tag.
- `src/examples/*.yml` pin the version being released, which does not exist yet
  while the PR is open. That is expected — the examples are registry
  documentation, not resolved config.
