#!/usr/bin/env bash
# Checks that the marketplace and every plugin it lists are well-formed:
# valid JSON, each listed plugin exists with a matching name, every skill
# has a SKILL.md with name and description front matter, and shell scripts parse.
set -euo pipefail
root=$(jq -r '.metadata.pluginRoot // "./plugins"' .claude-plugin/marketplace.json)
fail=0
err() { echo "::error::$*"; fail=1; }

for f in $(git ls-files '*.json'); do jq empty "$f" || err "invalid JSON: $f"; done

for name in $(jq -r '.plugins[].source' .claude-plugin/marketplace.json); do
  dir="$root/$name"
  [ -f "$dir/.claude-plugin/plugin.json" ] || { err "missing $dir/.claude-plugin/plugin.json"; continue; }
  pname=$(jq -r .name "$dir/.claude-plugin/plugin.json")
  [ "$pname" = "$name" ] || err "$dir: plugin.json name '$pname' does not match '$name'"
  for skill in "$dir"/skills/*/; do
    md="$skill/SKILL.md"
    [ -f "$md" ] || { err "missing $md"; continue; }
    head -20 "$md" | grep -q '^name:' || err "$md: no name in front matter"
    head -20 "$md" | grep -q '^description:' || err "$md: no description in front matter"
  done
done

for s in $(git ls-files '*.sh'); do bash -n "$s" || err "shell syntax: $s"; done

[ $fail -eq 0 ] && echo "All plugins valid."
exit $fail
