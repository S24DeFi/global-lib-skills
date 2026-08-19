---
name: public-release-prep
description: Audit a private git repository for secrets and personally-identifying info before it goes public, then carry out the cleanup. Use this whenever the user wants to open-source a repo, flip a GitHub repo from private to public, "clean up before going public," or asks whether a repo is safe to share externally — even if they don't mention secrets or PII explicitly. Also trigger on requests to scrub git history, squash commits for a public release, or remove an old email/employer/personal path from a repo's history. Covers the full exposure surface (every branch, tag, and PR ref GitHub actually serves), not just the default branch, and helps decide between rewriting history in place vs. starting a fresh repo.
---

# Public Release Prep

A repo that looks clean on its default branch can still leak things once it's
public, because GitHub serves more than `main`: every branch, every tag, and
every closed/merged pull request's diff stay browsable (and `git fetch
origin refs/pull/N/head` still works) for as long as the repository exists.
Scanning only the current tree, or only `git log main`, misses whatever was
fixed, force-pushed over, or squash-merged along the way — which is exactly
the stuff people forget is still sitting there.

The job here has two parts: find everything that's actually reachable, then
help the user pick a remediation that matches how bad it is. Don't skip
straight to "let's squash it" — squashing only rewrites branches you control;
it does nothing to old PR pages or tags, which is a common surprise.

## Step 1: Scan the full exposure surface

Run the bundled script, which fetches every ref and scans both the current
tip (what's immediately visible) and the full history (what's technically
reachable):

```bash
bash scripts/scan_history.sh /path/to/repo
```

It prints a working directory containing:
- `tip_emails.txt`, `tip_paths.txt`, `tip_secrets.txt` — hits in the current
  default-branch tree
- `history_secrets.txt`, `history_emails.txt`, `history_paths.txt`,
  `history_ips.txt` — hits anywhere across all branches/tags/PR refs
- `identities.txt` — every distinct commit author/committer identity ever
  used in the repo
- `tag_reachability.txt` — for each tag, whether it's an ancestor of a live
  branch or a dangling artifact only reachable by its own ref

The regexes are a starting point, not the whole job. Read through the hits
yourself — greps produce false positives (template placeholders like
`your@example.com`, doc examples of what *not* to hardcode) and false
negatives (a script's `.filter(Boolean)`-style approach won't catch a
company name or a person's name that isn't in an email or path pattern).
When something looks interesting, pull the surrounding context and the
commit it's from:

```bash
grep -n "<hit>" <fullhistory-file> | head
# then look a few hundred lines around each match for the commit header
```

For anything found only in history (not the current tip), confirm whether
it's reachable from a branch that's actually going public:

```bash
git merge-base --is-ancestor <commit-sha> origin/main && echo "on main" || echo "not on main"
```

This distinction matters a lot for what happens next — see Step 3.

## Step 2: Triage findings by severity

Group what you found roughly like this, and say so plainly to the user
rather than burying it in a wall of grep output:

- **Critical** — real secrets (API keys, tokens, private keys, passwords)
  anywhere in history, reachable or not. These need rotating regardless of
  what happens to the repo.
- **High** — anything that identifies a specific person + sensitive context:
  an employer's email domain, a workplace-specific file path, a phone
  number, a home address. Especially bad if it's in a *currently reachable*
  ref (a live branch or a tag someone would actually see).
- **Medium** — things that are personally identifying but low-stakes on
  their own (a local username in an old path, a personal dev alias) —
  worth cleaning up but not launch-blocking by themselves.
- **Low / non-issues** — the repo owner's own already-public info (their own
  company email if this *is* their company's repo, generic placeholders).
  Say explicitly why something in this bucket is fine — it saves the user
  from re-litigating it.

## Step 3: Decide on a remediation — this needs the user's call

Lay out the real tradeoff rather than defaulting to "just squash it":

| Approach | Fixes | Doesn't fix |
|---|---|---|
| Delete a specific tag/branch ref | That one artifact | Everything else |
| Squash the branches going public into clean history | What a normal clone/browse of those branches shows | Old closed/merged PR pages — GitHub keeps serving these from their own refs independent of what you do to your branches. If a High-severity finding lives in an old PR's diff, it survives a squash. |
| Start a fresh repo (single clean initial commit, no old refs) | Everything — nothing carries over that you didn't explicitly bring | Requires abandoning or archiving the old repo's PR/issue history; existing collaborators/forks need to switch remotes |

If nothing above Medium severity turned up, or everything sensitive is
confined to refs the user is fine deleting, squash-in-place is proportionate
and much less disruptive. If a Critical or High finding is baked into old
PR history, be direct that only a fresh repo actually closes the gap — this
is a case where you should say the harder thing rather than let the user
pick the easier option without knowing it won't fully work.

Use `AskUserQuestion` here rather than deciding for them: this is a
consequential, partly-irreversible choice (force-pushing shared history, or
starting over on issue/PR history) and the right answer depends on how
public-facing the old PR history actually is to this user's threat model.

## Step 4: Execute

**Fresh repo:**
1. Confirm the new repo exists (create it if you have permission; many CI/
   integration setups don't grant repo-creation — if creation 403s, ask the
   user to create an empty, private repo by hand and tell you when it's
   done, then continue).
2. Build one clean commit from the tree that's actually meant to go out —
   not necessarily whatever the default branch happens to be right now if
   there's a pending PR with fixes that should be included:
   ```bash
   git checkout --orphan clean-main <ref-with-the-intended-final-tree>
   git status --short   # sanity check: does the file list look right, nothing extra staged?
   git commit -m "Initial commit: <project>" # use a real identity, not a placeholder
   ```
3. Re-run the scan against the new orphan commit's tree before pushing —
   confirm the specific findings from Step 2 are actually gone, don't just
   assume the fresh-start fixed them.
4. Push, then tell the user plainly what happened to the old repo (nothing,
   unless asked) — it still holds the exposure, so it should stay private or
   get archived, not deleted reflexively in case it's needed for reference.

**Squash-in-place:** same orphan-commit mechanism, on the existing remote,
force-pushed. Flag that this breaks any existing local clones/forks people
have, and that it's a hard-to-reverse operation — confirm before force-pushing.

## Step 5: Branch protection (once the target repo is settled)

This isn't strictly a "was there PII" question, but it's the natural next
step right before flipping visibility, and worth doing in the same pass:

- Require a pull request before merging, with required review — point at
  `CODEOWNERS` if the repo has one
- Require the repo's own CI status checks to pass before merging
- Require branches to be up to date before merging
- Disallow force pushes and branch deletion on the protected branch
- If the org's ruleset UI only offers literal prefix matching (no regex) for
  branch-name rules, that can't express "one of several type prefixes" in a
  single rule — either switch to a regex-based rule
  (`^(bugfix|enhancement|debt)/[a-z0-9]+(-[a-z0-9]+)*$` as a starting point,
  adjusted to the team's actual convention) or add one rule per prefix

No GitHub MCP tool reliably covers repo-settings/branch-protection writes —
check what's actually available before promising to do this
programmatically, and hand the user the exact settings to click through
manually if nothing covers it.

## Before finishing

Re-state, in plain terms, what's now true: what's public-safe, what's still
sitting in the old repo and needs to stay private, and whether anything
(leaked real secrets, specifically) needs rotating regardless of what
happens to the repo — a secret that was ever committed should be treated as
burned even if history gets rewritten, since it may already be cached,
forked, or scraped.
