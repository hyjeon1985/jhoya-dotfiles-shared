#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BEGIN_MARKER='# >>> jhoya-dotfiles-root-home-bridge >>>'
END_MARKER='# <<< jhoya-dotfiles-root-home-bridge <<<'
ROOT_HOME="${JHOYA_ROOT_HOME:-/root}"
REAL_HOME_DEFAULT="${HOME:-}"

usage() {
  cat <<'HELP'
Usage: ./scripts/fix_root_home_bridge.sh <apply|remove|status> [--real-home PATH] [--root-home PATH]

Operator-only helper for special hosts where root login startup files source
root-owned bash files while the intended working home lives elsewhere.

Behavior:
  - only inspects existing files under the root home
  - prefers ~/.bashrc itself when it already rewrites HOME away from /root
  - otherwise patches the first file in bash login precedence order that
    already appears to source ~/.bashrc
  - inserts or updates a managed block without creating new login files
  - never creates new login files

Environment overrides:
  JHOYA_ROOT_HOME   root home to inspect (defaults to /root)
HELP
}

log() {
  printf '[%s] %s\n' "$1" "$2"
}

die() {
  log ERROR "$1" >&2
  exit 1
}

ensure_root() {
  [ "${JHOYA_ALLOW_NONROOT_TEST:-0}" = "1" ] && return 0
  [ "$(id -u)" -eq 0 ] || die "this operator utility must run as root"
}

infer_real_home() {
  local value="$1"
  if [ -n "$value" ] && [ "$value" != "$ROOT_HOME" ]; then
    printf '%s\n' "$value"
    return 0
  fi
  die "unable to infer target home automatically; pass --real-home /path/to/home"
}

file_sources_bashrc() {
  local file="$1"
  [ -f "$file" ] || return 1
  grep -Eq '(^|[[:space:]])(\.|source)[[:space:]]+([^[:space:]]*/)?~?/?\.bashrc([[:space:]]|$)' "$file"
}

file_rewrites_home_away_from_root() {
  local file="$1"
  [ -f "$file" ] || return 1
  awk -v root_home="$ROOT_HOME" '
    /^[[:space:]]*(export[[:space:]]+)?HOME=/ {
      line=$0
      sub(/^[[:space:]]*(export[[:space:]]+)?HOME=/, "", line)
      gsub(/["'\''[:space:]]/, "", line)
      if (line != "" && line != root_home) {
        found=1
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$file"
}

detect_target() {
  local bashrc_candidate="$ROOT_HOME/.bashrc"
  local candidate

  if file_rewrites_home_away_from_root "$bashrc_candidate"; then
    printf 'bashrc\t%s\n' "$bashrc_candidate"
    return 0
  fi

  for candidate in \
    "$ROOT_HOME/.bash_profile" \
    "$ROOT_HOME/.bash_login" \
    "$ROOT_HOME/.profile"
  do
    if file_sources_bashrc "$candidate"; then
      printf 'login\t%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

render_block() {
  local mode="$1"
  local real_home="$2"
  if [ "$mode" = "bashrc" ]; then
    cat <<BLOCK
$BEGIN_MARKER
if [ "\${HOME:-}" != "$ROOT_HOME" ] && [ -f "\$HOME/.bashrc" ] && [ "\${JHOYA_BASHRC_BOOTSTRAPPED:-0}" != "1" ]; then
  export JHOYA_BASHRC_BOOTSTRAPPED=1
  . "\$HOME/.bashrc"
fi
$END_MARKER
BLOCK
    return 0
  fi
  cat <<BLOCK
$BEGIN_MARKER
export HOME=$(printf '%q' "$real_home")
export XDG_CONFIG_HOME=$(printf '%q' "$real_home/.config")
if [ "\$PWD" = "$ROOT_HOME" ]; then
  cd "\$HOME"
fi
$END_MARKER
BLOCK
}

strip_existing_block() {
  local file="$1"
  local output="$2"
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { print }
  ' "$file" > "$output"
}

write_block() {
  local file="$1"
  local mode="$2"
  local block="$3"
  local tmp_clean tmp_final

  tmp_clean="$(mktemp)"
  tmp_final="$(mktemp)"
  strip_existing_block "$file" "$tmp_clean"

  if [ "$mode" = "bashrc" ]; then
    cat "$tmp_clean" > "$tmp_final"
    if [ -s "$tmp_clean" ]; then
      printf '\n' >> "$tmp_final"
    fi
    printf '%s\n' "$block" >> "$tmp_final"
  else
    printf '%s\n' "$block" > "$tmp_final"
    if [ -s "$tmp_clean" ]; then
      printf '\n' >> "$tmp_final"
      cat "$tmp_clean" >> "$tmp_final"
    fi
  fi

  if cmp -s "$file" "$tmp_final"; then
    rm -f "$tmp_clean" "$tmp_final"
    log INFO "root-home bridge already up to date in $file"
    return 0
  fi

  mv "$tmp_final" "$file"
  rm -f "$tmp_clean"
  log INFO "installed root-home bridge in $file"
}

remove_block_if_present() {
  local file="$1"
  local tmp

  [ -f "$file" ] || return 0
  tmp="$(mktemp)"
  strip_existing_block "$file" "$tmp"
  if cmp -s "$file" "$tmp"; then
    rm -f "$tmp"
    return 0
  fi
  mv "$tmp" "$file"
  log INFO "removed root-home bridge from $file"
}

command_name="${1:-}"
shift || true

real_home_arg=""
root_home_arg=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --real-home)
      real_home_arg="$2"
      shift 2
      ;;
    --root-home)
      root_home_arg="$2"
      shift 2
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

if [ -n "$root_home_arg" ]; then
  ROOT_HOME="$root_home_arg"
fi

case "$command_name" in
  apply)
    ensure_root
    real_home="$(infer_real_home "${real_home_arg:-$REAL_HOME_DEFAULT}")"
    target_info="$(detect_target)" || die "no existing root startup file under $ROOT_HOME can be safely patched (needs either a HOME-rewriting ~/.bashrc or a login file that already sources ~/.bashrc)"
    target_mode="${target_info%%$'\t'*}"
    target_file="${target_info#*$'\t'}"
    write_block "$target_file" "$target_mode" "$(render_block "$target_mode" "$real_home")"
    printf 'target_mode=%s\n' "$target_mode"
    printf 'target=%s\n' "$target_file"
    printf 'real_home=%s\n' "$real_home"
    ;;
  remove)
    ensure_root
    for file in "$ROOT_HOME/.bashrc" "$ROOT_HOME/.bash_profile" "$ROOT_HOME/.bash_login" "$ROOT_HOME/.profile"; do
      remove_block_if_present "$file"
    done
    ;;
  status)
    target_info="$(detect_target || true)"
    if [ -z "$target_info" ]; then
      printf '%s\n' 'status=no-target'
      printf 'root_home=%s\n' "$ROOT_HOME"
      exit 0
    fi
    target_mode="${target_info%%$'\t'*}"
    target_file="${target_info#*$'\t'}"
    if grep -Fq "$BEGIN_MARKER" "$target_file"; then
      printf '%s\n' 'status=managed'
    else
      printf '%s\n' 'status=unmanaged'
    fi
    printf 'target_mode=%s\n' "$target_mode"
    printf 'target=%s\n' "$target_file"
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
