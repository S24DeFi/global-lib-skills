#!/usr/bin/env bash
# Scans a git repo's FULL exposure surface (every branch, tag, and PR ref) for
# secrets and personally-identifying info, before the repo goes public.
#
# Why "full exposure surface" instead of just the default branch: GitHub keeps
# closed/merged PR diffs and old tags browsable indefinitely, independent of
# whatever the current branch looks like. A clean `main` does not mean a clean
# repo. This script fetches everything GitHub would actually serve to a public
# visitor and scans all of it, then separately flags what's reachable from a
# live branch (fix it by editing forward) vs. only reachable via a dangling
# ref like a tag or an old PR head (fix requires deleting the ref, or is not
# fixable at all short of starting a new repo).
#
# Usage: scan_history.sh [path-to-repo]  (defaults to cwd)

set -euo pipefail
cd "${1:-.}"

OUT="$(mktemp -d)"
echo "Working dir: $OUT" >&2

echo "==> Fetching every branch, tag, and PR ref from origin..." >&2
git fetch origin '+refs/heads/*:refs/remotes/origin/*' '+refs/tags/*:refs/tags/*' >&2 2>&1 || true
# PR refs are GitHub-specific and only exist if the remote is GitHub; ignore failure elsewhere.
git fetch origin '+refs/pull/*/head:refs/remotes/origin/pr/*' >&2 2>&1 || true

DEFAULT_BRANCH="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#origin/##' || echo main)"

echo "==> Dumping full history across every ref (this is the full exposure surface)..." >&2
git log --all -p > "$OUT/fullhistory.txt" 2>/dev/null

echo "==> Scanning current tip of $DEFAULT_BRANCH (what's visible immediately on the repo page)..." >&2
git grep -inoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "origin/$DEFAULT_BRANCH" -- . 2>/dev/null \
  | grep -viE '@example\.|@company\.com|noreply@|users\.noreply\.github\.com' \
  > "$OUT/tip_emails.txt" || true
git grep -inE '/(Users|home)/[a-zA-Z0-9_.-]+' "origin/$DEFAULT_BRANCH" -- . 2>/dev/null > "$OUT/tip_paths.txt" || true
git grep -inE '(api[_-]?key|secret[_-]?key|access[_-]?key|private[_-]?key|password\s*=|passwd\s*=|token\s*=|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|xox[baprs]-|AIza[0-9A-Za-z_-]{20,}|eyJ[A-Za-z0-9_-]{10,}\.)' \
  "origin/$DEFAULT_BRANCH" -- . 2>/dev/null > "$OUT/tip_secrets.txt" || true

echo "==> Scanning ALL history (every branch/tag/PR ref) for the same patterns..." >&2
grep -inE '(api[_-]?key|secret[_-]?key|access[_-]?key|private[_-]?key|BEGIN (RSA|OPENSSH|EC|DSA|PGP) PRIVATE KEY|password\s*=|passwd\s*=|token\s*=|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|xox[baprs]-|AIza[0-9A-Za-z_-]{20,})' \
  "$OUT/fullhistory.txt" | grep -v '^diff\|^index\|^---\|^+++' | sort -u > "$OUT/history_secrets.txt" || true
grep -inoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$OUT/fullhistory.txt" \
  | sort -u | grep -viE '@example\.|@company\.com|noreply@|users\.noreply\.github\.com' > "$OUT/history_emails.txt" || true
grep -inE '/(Users|home)/[a-zA-Z0-9_.-]+' "$OUT/fullhistory.txt" \
  | grep -v '^diff\|^index' | sort -u > "$OUT/history_paths.txt" || true
grep -inoE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$OUT/fullhistory.txt" | sort -u \
  | grep -vE '0\.0\.0\.0|127\.0\.0\.1|255\.255\.255|192\.168\.|10\.0\.0|172\.(1[6-9]|2[0-9]|3[01])\.' > "$OUT/history_ips.txt" || true

echo "==> Listing every author/committer identity across all refs..." >&2
git log --all --format='%an <%ae> | committer: %cn <%ce>' | sort -u > "$OUT/identities.txt"

echo "==> Listing tags and whether each is reachable from a live branch..." >&2
: > "$OUT/tag_reachability.txt"
for tag in $(git tag -l); do
  reachable="no"
  for b in $(git for-each-ref --format='%(refname)' refs/remotes/origin/ 2>/dev/null); do
    if git merge-base --is-ancestor "$tag" "$b" 2>/dev/null; then reachable="yes ($b)"; break; fi
  done
  echo "$tag -> reachable from live branch: $reachable" >> "$OUT/tag_reachability.txt"
done

echo "" >&2
echo "==> Scan complete. Results in: $OUT" >&2
echo "$OUT"
