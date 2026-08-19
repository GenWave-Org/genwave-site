#!/usr/bin/env bash
# install.sh — the one-liner bootstrap: `curl -fsSL https://install.genwaveradio.com | bash`
# (SPEC F133.1-.3, STORY-347). Read it before you pipe it — that's the trust posture.
#
# Checks curl/git/docker, resolves the latest release tag, shallow-clones GenWave at that tag
# into a prompted directory (default ~/genwave), execs ./setup.sh — the wizard takes it from
# there. Git is the delivery + integrity mechanism; never fetches/runs anything but a `git
# clone` of the public repo. Never sudo — a missing docker group prints the fix and exits.
#
# Tag rule: releases are plain `vMAJOR.MINOR.PATCH` tags (`git tag -l` in the app repo, cross-
# checked against `gh release list` — the one outlier, v0.1.0-rc.1, was never its "Latest").
# So "latest" = highest vX.Y.Z by version sort, pre-releases excluded on purpose.
# `git ls-remote --tags` needs no local clone; `--refs` drops peel lines, the `^{}` grep below
# is a defensive second net for a git predating --refs.
#
# Test seams (each a no-op on the real path): GW_INSTALL_REF overrides tag resolution with any
# ref (branch/SHA/tag) — for exercising this script before a release ships setup.sh at all (the
# wizard train is unreleased as of T323). GW_INSTALL_REPO overrides the clone source (default
# the public GitHub repo) — points tests at a local mirror instead of the network. GW_INSTALL_
# NO_EXEC stops right before `exec ./setup.sh` and prints what would have run, so a test can
# prove the clone landed without launching the real wizard.
set -euo pipefail

REPO_URL="${GW_INSTALL_REPO:-https://github.com/GenWave-Org/genwave.git}"
DEFAULT_DIR="$HOME/genwave"

resolve_ref() {
  if [ -n "${GW_INSTALL_REF:-}" ]; then
    printf '%s\n' "$GW_INSTALL_REF"
    return
  fi
  local tag
  tag="$(git ls-remote --tags --refs "$REPO_URL" 2>/dev/null \
    | awk '{print $2}' | sed 's#^refs/tags/##' | grep -v '\^{}$' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)"
  [ -n "$tag" ] || { echo "Could not resolve a release tag from $REPO_URL" >&2; exit 1; }
  printf '%s\n' "$tag"
}

# A curl|bash pipe occupies stdin, so prompts read from the controlling terminal (/dev/tty)
# instead — the classic curl|bash trap is reading the piped SCRIPT itself as the answer. A
# headless/CI/detached caller may have no controlling terminal at all — opening /dev/tty then
# fails at run time (ENXIO) even though the path exists, so this attempts the open itself
# (fd 3) rather than trusting a [ -r /dev/tty ] permission check: take the default and say so
# rather than hang.
prompt_target_dir() {
  local answer=""
  if { exec 3<> /dev/tty; } 2>/dev/null; then
    printf 'Install directory [%s]: ' "$DEFAULT_DIR" >&3
    IFS= read -r answer <&3 || true
    exec 3<&-
  else
    echo "No terminal to prompt on — using the default install directory: $DEFAULT_DIR" >&2
  fi
  printf '%s\n' "${answer:-$DEFAULT_DIR}"
}

check_prereqs() {
  for bin in curl git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "Missing required tool: $bin" >&2; exit 1; }
  done
  command -v docker >/dev/null 2>&1 || {
    echo "Docker is not installed. Install it: https://docs.docker.com/engine/install/" >&2
    exit 1
  }
  if ! docker info >/dev/null 2>&1; then
    echo "Docker is installed, but this user can't reach the daemon." >&2
    echo "Add yourself to the docker group and re-login:" >&2
    echo "  sudo usermod -aG docker \$USER   (then log out/in, or: newgrp docker)" >&2
    echo "Then re-run this installer." >&2
    exit 1
  fi
}

is_genwave_checkout() { [ -d "$1/.git" ] && [ -f "$1/launch.sh" ]; }

run_setup() {
  cd "$1"
  if [ -n "${GW_INSTALL_NO_EXEC:-}" ]; then
    echo "GW_INSTALL_NO_EXEC set — would exec ./setup.sh in $1 now." >&2
    exit 0
  fi
  exec ./setup.sh
}

check_prereqs
target_dir="$(prompt_target_dir)"

if [ -e "$target_dir" ] && [ -n "$(ls -A "$target_dir" 2>/dev/null)" ]; then
  if ! is_genwave_checkout "$target_dir"; then
    echo "$target_dir already exists and isn't a GenWave checkout." >&2
    echo "Refusing to touch it — pick an empty or different directory." >&2
    exit 1
  fi
  if [ ! -f "$target_dir/setup.sh" ]; then
    echo "$target_dir is a GenWave checkout, but it predates the setup wizard (no setup.sh)." >&2
    echo "Update it, then re-run this installer:" >&2
    echo "  git -C \"$target_dir\" fetch --tags && git -C \"$target_dir\" checkout $(resolve_ref)" >&2
    exit 1
  fi
  echo "Existing GenWave checkout found at $target_dir — handing off to its setup.sh." >&2
  run_setup "$target_dir"
fi

ref="$(resolve_ref)"
echo "Cloning GenWave @ $ref into $target_dir ..." >&2
git clone --quiet -c advice.detachedHead=false --depth 1 --branch "$ref" "$REPO_URL" "$target_dir"
run_setup "$target_dir"
