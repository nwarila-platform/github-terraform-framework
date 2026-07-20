#!/usr/bin/env bash
# Regression test for the workspace-assembly dotfile guard.
#
# A repo definition named `.github.yml` is a dotfile. If the guard that decides
# whether to copy a definitions directory cannot see dotfiles, a directory
# holding only that file reads as empty, the copy is skipped, the repository
# stops being declared, and Terraform plans to DELETE it along with its rulesets
# and branch default. Nothing sets prevent_destroy on repositories to catch that.
#
# This asserts the guard used by .github/workflows/reusable-terraform-deploy.yaml
# sees a dotfile-only directory, and demonstrates that the previous `compgen -G`
# form did not.
set -euo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/dotfile-only" "$tmp/normal" "$tmp/empty"
touch "$tmp/dotfile-only/.github.yml"
touch "$tmp/normal/example.yml"

fail=0

check() {
  local dir="$1" expected="$2" label="$3"
  local got="empty"
  if [ -n "$(ls -A "$dir")" ]; then got="non-empty"; fi
  if [ "$got" = "$expected" ]; then
    echo "  PASS  $label -> $got"
  else
    echo "  FAIL  $label -> $got (expected $expected)"
    fail=1
  fi
}

echo "guard in use (ls -A):"
check "$tmp/dotfile-only" "non-empty" "directory containing only .github.yml"
check "$tmp/normal"       "non-empty" "directory containing example.yml"
check "$tmp/empty"        "empty"     "genuinely empty directory"

# Demonstrate the regression this replaced: the old guard misreports the
# dotfile-only case, which is what made the repository disappear.
echo
echo "previous guard (compgen -G), for contrast:"
if compgen -G "$tmp/dotfile-only/*" > /dev/null; then
  echo "  FAIL  old guard saw the dotfile (unexpected — regression test is stale)"
  fail=1
else
  echo "  OK    old guard could NOT see .github.yml — the bug this test pins"
fi

exit "$fail"
