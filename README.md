# global-lib-skills

S24DeFi's shared Claude Code skills — reusable workflows we've built once and want available on any machine or repo, not copy-pasted per-project.

## Using this marketplace

```bash
/plugin marketplace add S24DeFi/global-lib-skills
/plugin install public-release-prep@global-lib-skills
```

Update later with:

```bash
/plugin marketplace update global-lib-skills
```

## Plugins

### public-release-prep

Audits a private git repo's **full** exposure surface — every branch, tag, and PR ref, not just the default branch — for secrets and personally-identifying info before it goes public. Helps decide between rewriting history in place vs. starting a fresh repo, since squashing a branch doesn't remove old closed/merged PR pages GitHub keeps serving. Then walks through execution and branch-protection setup.

Trigger it by asking Claude to prep a repo for open-sourcing, check if a repo is safe to make public, or clean up git history before a release.

## Adding a new skill

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

Register it in `.claude-plugin/marketplace.json`'s `plugins` array (source is the directory name relative to `metadata.pluginRoot`), then push. Teammates pick it up with `/plugin marketplace update global-lib-skills`.
