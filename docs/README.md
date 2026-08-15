# docs/

[`ENGINEERING-NOTES.md`](ENGINEERING-NOTES.md) is the exception to everything below: it's written to be read from outside. Three defects that a green 743-test suite did not catch, what the tests were measuring instead, and the five testing rules that came out of it.

Everything else under `docs/` — `DESIGN-*.md`, `BRIEF-*.md`, `PLANNING.md`, `IMPL-*.md`, `CHECKLIST-*.md` — is a maintainer-facing design and implementation record: open questions and the decisions made on them, and the results reported back. It documents *how* and *why* the library reached its current shape, for whoever maintains it next.

If you're using ABPlayerKit as a consumer, you don't need any of this. Start with the root [`README.md`](../README.md) (or [`README.ko.md`](../README.ko.md)) and the DocC documentation bundled with each target (`ABPlayerKit.docc`, `ABPlayerKitControls.docc`, `ABPlayerKitMetrics.docc`, `ABPlayerKitCache.docc`) — those are the supported, user-facing references.

## Retired: `briefs/`

`docs/briefs/` held 85 files (1.4 MB) of per-round working material — work-package briefs, the results reported back against them, and round review records. It was process exhaust rather than a reference: larger than `Sources/` and `Tests/` combined, written one round at a time, and not something a reader of this repository needs.

It was removed from the tree rather than rewritten. Nothing is lost — every file is still in git history and can be read directly:

```bash
git ls-tree -r --name-only v0.4.0 -- docs/briefs
git show v0.4.0:docs/briefs/DESIGN-round6-core.md
```

The conclusions worth keeping already live outside it: the architecture and rationale in [`DESIGN-ABPlayerKit.md`](DESIGN-ABPlayerKit.md), the API-stability policy in [`POLICY-api-stability.md`](POLICY-api-stability.md), the root README's "Design Rationale" section, and [`ENGINEERING-NOTES.md`](ENGINEERING-NOTES.md).
