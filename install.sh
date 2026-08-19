#!/usr/bin/env bash
# install.sh — the one-liner bootstrap: `curl -fsSL https://install.genwaveradio.com | bash`
# (SPEC F133.1-.3, STORY-347). Read it before you pipe it — that's the trust posture.
#
# Checks curl/git/docker, resolves the latest release tag, shallow-clones GenWave at that tag
# into a prompted directory (default ~/genwave), and — once the clone actually has it — execs
# ./setup.sh, the wizard taking it from there. A release that predates the wizard (no
# setup.sh) leaves the clone in place and says so plainly rather than exec'ing a file that
# isn't there. Git is the delivery + integrity mechanism; never fetches/runs anything but a
# `git clone` of the public repo. Never sudo — a missing docker group prints the fix and exits.
#
# Tag rule: releases are plain `vMAJOR.MINOR.PATCH` tags (`git tag -l` in the app repo, cross-
# checked against `gh release list` — the one outlier, v0.1.0-rc.1, was never its "Latest").
# So "latest" = highest vX.Y.Z by version sort, pre-releases excluded on purpose.
# `git ls-remote --tags --refs` needs no local clone and already drops the annotated-tag peel
# (`^{}`) lines on its own.
#
# Test seams (each a no-op on the real path): GW_INSTALL_REF overrides tag resolution with any
# ref (branch/SHA/tag) — for exercising this script before a release ships setup.sh at all (the
# wizard train is unreleased as of T323). GW_INSTALL_REPO overrides the clone source (default
# the public GitHub repo) — points tests at a local mirror instead of the network. GW_INSTALL_
# NO_EXEC stops right before `exec ./setup.sh` and prints what would have run, so a test can
# prove the clone landed without launching the real wizard.
#
# Truncation safety: everything with a real side effect lives inside main(), called on the
# very last line. A stream cut short anywhere inside main()'s body (`head -c N | bash`, a
# flaky curl) leaves the function definition syntactically incomplete — bash refuses to define
# it at all, so nothing in it ever runs. Only a cut landing at-or-past the final `main "$@"`
# line runs the real thing, in full.
set -euo pipefail

resolve_ref() {
  if [ -n "${GW_INSTALL_REF:-}" ]; then
    printf '%s\n' "$GW_INSTALL_REF"
    return
  fi
  local tag
  tag="$(git ls-remote --tags --refs "$REPO_URL" 2>/dev/null \
    | awk '{print $2}' | sed 's#^refs/tags/##' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)"
  [ -n "$tag" ] || { echo "Could not resolve a release tag from $REPO_URL" >&2; exit 1; }
  printf '%s\n' "$tag"
}

# `read` never tilde-expands a prompted answer (that's a shell-parse-time thing, and this
# value came from a variable) — so a typed `~/genwave` would otherwise become a literal `~`
# directory. No eval: just the two shapes worth handling.
expand_tilde() {
  case "$1" in
    \~) printf '%s\n' "$HOME" ;;
    \~/*) printf '%s\n' "$HOME/${1#\~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# A curl|bash pipe occupies stdin, so this prompt reads from the controlling terminal
# (/dev/tty) instead — the classic curl|bash trap is reading the piped SCRIPT itself as the
# answer. A headless/CI/detached caller may have no controlling terminal at all — opening
# /dev/tty then fails at run time (ENXIO) even though the path exists, so this attempts the
# open itself (fd 3) rather than trusting a [ -r /dev/tty ] permission check: take the default
# and say so rather than hang.
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
  local info_err
  if ! info_err="$(docker info 2>&1 >/dev/null)"; then
    if printf '%s' "$info_err" | grep -qi "permission denied"; then
      echo "Docker is installed, but this user can't reach the daemon (permission denied)." >&2
      echo "Add yourself to the docker group and re-login:" >&2
      echo "  sudo usermod -aG docker \$USER   (then log out/in, or: newgrp docker)" >&2
    else
      echo "Docker is installed, but the daemon doesn't seem to be running." >&2
      echo "Start it: sudo systemctl start docker   (on desktop: start Docker Desktop)" >&2
      echo "Check it: docker info" >&2
    fi
    echo "Then re-run this installer." >&2
    exit 1
  fi
}

# .git/ + launch.sh alone is a thin signature; compose.yaml narrows the false-positive blast
# radius further before this script hands off execution to a foreign setup.sh.
is_genwave_checkout() {
  [ -d "$1/.git" ] && [ -f "$1/launch.sh" ] && [ -f "$1/compose.yaml" ]
}

run_setup() {
  cd "$1"
  if [ -n "${GW_INSTALL_NO_EXEC:-}" ]; then
    echo "GW_INSTALL_NO_EXEC set — would exec ./setup.sh in $1 now." >&2
    exit 0
  fi
  # curl|bash (and `cat install.sh | bash`) hand THIS script's own body to bash over stdin —
  # bash then reports $0 as bash/sh rather than a file path. That means stdin is already spent
  # before setup.sh's own interactive interview (its stdin answer channel) ever gets a turn, so
  # fd 0 is re-pointed at the controlling terminal for the child in that case only, and only
  # when stdin isn't already a terminal itself. A file invocation (`bash install.sh`, optionally
  # `< answers.txt` for a scripted interview) keeps $0 == the script's path — stdin there is the
  # caller's own deliberate choice, left untouched.
  case "$0" in
    bash|-bash|sh|-sh)
      if [ ! -t 0 ]; then
        { exec 0<> /dev/tty; } 2>/dev/null || true
      fi
      ;;
  esac
  exec ./setup.sh
}

main() {
  if [ -z "${HOME:-}" ]; then
    echo "HOME isn't set — can't pick a default install directory." >&2
    echo "Re-run with HOME set, or answer the directory prompt interactively." >&2
    exit 1
  fi
  REPO_URL="${GW_INSTALL_REPO:-https://github.com/GenWave-Org/genwave.git}"
  DEFAULT_DIR="$HOME/genwave"

  check_prereqs
  local target_dir
  target_dir="$(prompt_target_dir)"
  target_dir="$(expand_tilde "$target_dir")"

  if [ -e "$target_dir" ] && [ -n "$(ls -A "$target_dir" 2>/dev/null)" ]; then
    if ! is_genwave_checkout "$target_dir"; then
      echo "$target_dir already exists and isn't a GenWave checkout." >&2
      echo "Refusing to touch it — pick an empty or different directory." >&2
      exit 1
    fi
    if [ ! -f "$target_dir/setup.sh" ]; then
      local latest_ref current_tag
      latest_ref="$(resolve_ref)"
      current_tag="$(git -C "$target_dir" describe --tags --exact-match 2>/dev/null || true)"
      if [ -n "$current_tag" ] && [ "$current_tag" = "$latest_ref" ]; then
        echo "$target_dir is already at $latest_ref — the latest release — it just predates the setup wizard." >&2
        echo "The wizard ships in a future release; there's nothing to update yet." >&2
      else
        echo "$target_dir is a GenWave checkout, but it predates the setup wizard (no setup.sh)." >&2
        echo "Update it, then re-run this installer:" >&2
        echo "  git -C \"$target_dir\" fetch --tags && git -C \"$target_dir\" checkout $latest_ref" >&2
      fi
      exit 1
    fi
    echo "Existing GenWave checkout found at $target_dir — handing off to its setup.sh." >&2
    run_setup "$target_dir"
  fi

  local ref
  ref="$(resolve_ref)"
  echo "Cloning GenWave @ $ref into $target_dir ..." >&2
  git clone --quiet -c advice.detachedHead=false --depth 1 --branch "$ref" -- "$REPO_URL" "$target_dir"
  if [ ! -f "$target_dir/setup.sh" ]; then
    echo "GenWave $ref cloned to $target_dir, but this release predates the setup wizard (no setup.sh)." >&2
    echo "The wizard ships in a future release — this clone is intact and ready for it; nothing more to do yet." >&2
    exit 1
  fi
  run_setup "$target_dir"
}

main "$@"
