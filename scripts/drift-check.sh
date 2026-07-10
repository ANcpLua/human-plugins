#!/bin/zsh
# drift-check — MANDATORY first action for any agent working in this repo.
# Exit 0: no drift, proceed. Exit 1: drift found — STOP and produce a Drift
# Report per root CLAUDE.md before doing anything else.
set -u
cd "$(git rev-parse --show-toplevel)" || exit 2
drift=0

# 1. Uncommitted work is drift by definition.
if [[ -n "$(git status --porcelain)" ]]; then
  echo "DRIFT: uncommitted changes in working tree:"
  git status --short
  drift=1
fi

# 2. Every commit touching a tool must have updated that tool's CHANGELOG.md.
for tool in tools/*/; do
  if [[ ! -f "${tool}CHANGELOG.md" ]]; then
    echo "DRIFT: ${tool} has no CHANGELOG.md"
    drift=1
    continue
  fi
  last=$(git log -1 --format=%H -- "$tool" 2>/dev/null)
  [[ -z "$last" ]] && continue
  if ! git show --name-only --format= "$last" | grep -q "^${tool}CHANGELOG.md$"; then
    echo "DRIFT: ${tool} — last commit touching it did not update its CHANGELOG.md:"
    git log -1 --format='  %h %ad %s' --date=short -- "$tool"
    drift=1
  fi
done

# 3. Installed artifacts must match the repo copies.
check_installed() {  # $1 repo file, $2 installed file, $3 label
  if [[ -e "$2" ]]; then
    if ! diff -q "$1" "$2" >/dev/null 2>&1; then
      echo "DRIFT: installed $3 differs from repo copy ($2 vs $1)"
      drift=1
    fi
  else
    echo "DRIFT: $3 not installed ($2 missing) but tool is marked active"
    drift=1
  fi
}
check_installed tools/airpods-mic-guard/launchd/com.ancplua.airpods-mic-guard.plist \
  "$HOME/Library/LaunchAgents/com.ancplua.airpods-mic-guard.plist" \
  "airpods-mic-guard launchd plist"
[[ -x "$HOME/.local/bin/airpods-mic-guardd" ]] || {
  echo "DRIFT: airpods-mic-guardd binary missing from ~/.local/bin"
  drift=1
}

if (( drift )); then
  echo
  echo "DRIFT FOUND — STOP. Produce a Drift Report (root CLAUDE.md) before any other work."
  exit 1
fi
echo "no drift — proceed"
