
# global-lib-skills

Claude Code plugin marketplace. Reusable engineering workflows built once and installed anywhere, rather than copy-pasted per project.

## public-release-prep

Audits the full exposure surface of a private repository before it goes public, then walks through the cleanup.

**What it checks.** Not just the default branch. Every branch, every tag, and every pull request ref, including closed and merged PRs. It scans that entire surface for committed secrets, credentials, and personally identifying information, and reports what it found and where it lives. The scope is the point: most pre-release checks look at the working tree or `git log` on `main`, which is the smallest and least interesting part of what a repository actually exposes.

**Why it exists.** The standard advice for cleaning a repo before open-sourcing is incomplete in a way that is easy to miss. Squashing a branch or rewriting history removes the commit from your local graph, but GitHub keeps serving the old diffs on closed and merged pull request pages, and those refs stay reachable to anyone with the URL. A repo can pass a local audit, look clean in every tool you point at it, and still be leaking. That distinction drives a real decision, so the plugin surfaces it explicitly: rewrite history in place when the exposure is confined to reachable commits, or start a fresh repository with a squashed initial commit when a PR ref is already contaminated, because that is the only reliable fix once GitHub has the blob. It then walks execution and sets up branch protection so the next push doesn't undo the work.

### Install

```bash
/plugin marketplace add S24DeFi/global-lib-skills
/plugin install public-release-prep@global-lib-skills
```

Update later:

```bash
/plugin marketplace update global-lib-skills
```

### Usage

Ask Claude to prep a repo for open-sourcing, check whether a repo is safe to make public, or clean up git history before a release.

---

## Adding a skill

Each skill lives as its own plugin under `plugins/<name>/`:

```
plugins/<name>/
├── .claude-plugin/
│   └── plugin.json
└── skills/
    └── <name>/
        ├── SKILL.md
        └── scripts/        # optional bundled scripts
```

Register it in the `plugins` array in `.claude-plugin/marketplace.json` (source is the directory name relative to `metadata.pluginRoot`), then push. Pick it up elsewhere with `/plugin marketplace update global-lib-skills`.
