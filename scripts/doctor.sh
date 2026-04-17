#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/jhoya/state"
METADATA_PATH="$STATE_DIR/install-metadata.json"
CURRENT_UNINSTALL="${XDG_CONFIG_HOME:-$HOME/.config}/jhoya/bin/uninstall-current-install.sh"
QUIET=0
PLAN_ONLY=0
MISSING_REQUIRED=()

prepend_path_if_missing() {
  local path_dir="$1"
  case ":$PATH:" in
    *":$path_dir:"*) ;;
    *) PATH="$path_dir:$PATH" ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --quiet) QUIET=1 ;;
    --plan) PLAN_ONLY=1 ;;
    -h|--help)
      cat <<'HELP'
Usage: ./scripts/doctor.sh [--plan] [--quiet]

  --plan   shared-base install guidance only
  --quiet  show only warnings/errors/summary
HELP
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

prepend_path_if_missing "$HOME/.local/bin"

print_line() {
  [ "$QUIET" -eq 1 ] && return 0
  printf '%s\n' "$1"
}

note_missing() {
  MISSING_REQUIRED+=("$1")
}

check_cmd() {
  local cmd_name="$1"
  if command -v "$cmd_name" >/dev/null 2>&1; then
    print_line "[OK]      $cmd_name"
    return 0
  fi
  printf '[MISSING] %s\n' "$cmd_name"
  note_missing "$cmd_name"
  return 1
}

check_link() {
  local name="$1"
  local target="$2"

  if [ -L "$target" ] && [ "$(readlink "$target")" != "" ]; then
    case "$(readlink "$target")" in
      "$REPO_ROOT"/*)
        print_line "[OK]      $name"
        return 0
        ;;
    esac
  fi

  printf '[WARN]    %s not managed by shared-base repo\n' "$name"
  note_missing "$name"
  return 1
}

check_block() {
  local name="$1"
  local file="$2"
  local begin_marker="$3"

  if [ -f "$file" ] && grep -Fq "$begin_marker" "$file"; then
    print_line "[OK]      $name"
    return 0
  fi

  printf '[WARN]    %s missing from %s\n' "$name" "$file"
  note_missing "$name"
  return 1
}

print_plan() {
  cat <<'PLAN'
Shared-base required tool inventory:
- make bash git curl jq tmux
- uv uvx
- bw bws
- starship btop gh tombi

Shared-base managed assets currently include:
- tmux baseline config
- shared env templates
- shared bash/common shell content/adapters
- starship config
- shared fonts
- current uninstall contract + install metadata
- bash integration via the existing ~/.bashrc only
PLAN
}

if [ "$PLAN_ONLY" -eq 1 ]; then
  print_plan
  exit 0
fi

printf '== jhoya-dotfiles-shared doctor ==\n'

for cmd_name in make bash git curl jq tmux uv uvx bw bws starship btop gh tombi; do
  check_cmd "$cmd_name" || true
done

if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/plugins/catppuccin/tmux/catppuccin.tmux" ]; then
  print_line "[OK]      tmux catppuccin plugin"
else
  printf '[WARN]    missing tmux catppuccin plugin\n'
  note_missing "tmux catppuccin plugin"
fi

check_link "shared env-core" "$HOME/.config/jhoya/shared/env-core.sh" || true
check_link "shared term-ui" "$HOME/.config/jhoya/shared/term-ui.sh" || true
check_link "shared alias-public" "$HOME/.config/jhoya/shared/alias-public.sh" || true
check_link "bash env-core adapter" "$HOME/.config/jhoya/bashrc.d/20-env-core-bash.sh" || true
check_link "bash term-ui adapter" "$HOME/.config/jhoya/bashrc.d/22-term-ui-bash.sh" || true
check_link "bash alias-public adapter" "$HOME/.config/jhoya/bashrc.d/24-alias-public-bash.sh" || true
check_link "bash wezterm adapter" "$HOME/.config/jhoya/bashrc.d/25-wezterm-bash.sh" || true
check_link "bash starship adapter" "$HOME/.config/jhoya/bashrc.d/40-starship-bash.sh" || true
check_block "bash managed block" "$HOME/.bashrc" '# >>> jhoya-dotfiles >>>' || true
check_link "tmux config" "$HOME/.tmux.conf" || true
check_link "env template" "$HOME/.config/jhoya/.env.template" || true
check_link "secrets template" "$HOME/.config/jhoya/secrets/.env.template" || true
check_link "starship config" "$HOME/.config/starship.toml" || true

if [ -f "$METADATA_PATH" ]; then
  print_line "[OK]      install metadata"
else
  printf '[WARN]    missing install metadata: %s\n' "$METADATA_PATH"
  note_missing "install-metadata"
fi

if [ -x "$CURRENT_UNINSTALL" ]; then
  print_line "[OK]      current uninstall contract"
else
  printf '[WARN]    missing current uninstall contract: %s\n' "$CURRENT_UNINSTALL"
  note_missing "current-uninstall"
fi

printf '\nsummary:\n'
printf '  missing required/shared-base items: %s\n' "${#MISSING_REQUIRED[@]}"

if [ "${#MISSING_REQUIRED[@]}" -gt 0 ]; then
  print_plan
  exit 1
fi

exit 0
