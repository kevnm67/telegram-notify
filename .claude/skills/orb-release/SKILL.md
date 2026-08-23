---
name: orb-release
description: >
  Cut a production release of the telegram-notify orb: verify main is green,
  update CHANGELOG.md, tag vX.Y.Z, watch the publish job, verify the version
  in the registry and smoke-test it. Use when asked to "release", "tag",
  "publish vX.Y.Z" or "ship the orb".
---

# Orb release checklist

1. `git checkout main && git pull` — confirm the latest `main` pipeline is green
   (`lint_pack_test` + `test_deploy`, `publish_dev` succeeded).
2. Run `/live-test` once if anything in `src/` changed since the last release.
3. Move the `[Unreleased]` section of `CHANGELOG.md` under `## [X.Y.Z] - YYYY-MM-DD`
   (Keep a Changelog), open a PR for it, merge.
4. Tag and push: `git tag vX.Y.Z && git push origin vX.Y.Z` — the tag pipeline runs
   the integration jobs again and `publish_production` publishes `kevnm67/telegram-notify@X.Y.Z`.
5. Verify: `circleci orb info kevnm67/telegram-notify` shows the version;
   `circleci orb source kevnm67/telegram-notify@X.Y.Z | head`.
6. Update README/wiki version pins if the major changed; create a GitHub release with
   `gh release create vX.Y.Z --generate-notes`.

Versions are immutable — never republish; fix forward with a patch release.
