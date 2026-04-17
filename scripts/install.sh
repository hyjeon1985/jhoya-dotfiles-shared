#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="${JHOYA_STATE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/jhoya/state}"
BIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/jhoya/bin"
METADATA_PATH="$STATE_DIR/install-metadata.json"
CURRENT_UNINSTALL="$BIN_DIR/uninstall-current-install.sh"
MODE="${JHOYA_INSTALL_MODE:-standalone}"
VERSION="${JHOYA_INSTALL_VERSION:-0.3.0-slice4}"
GRADE="remote"
MANAGES_INSTALL_CONTRACT=1
JHOYA_STATE_DIR="$STATE_DIR"
JHOYA_MANAGED_SYMLINKS_TMP="${JHOYA_MANAGED_SYMLINKS_TMP:-$STATE_DIR/managed-symlinks.next.tsv}"
export JHOYA_STATE_DIR JHOYA_MANAGED_SYMLINKS_TMP

# shellcheck source=./link.sh
source "$SCRIPT_DIR/link.sh"

log() {
  printf '[%s] %s\n' "$1" "$2"
}

die() {
  log ERROR "$1" >&2
  exit 1
}

read_installed_metadata_field() {
  local field="$1"
  if [ ! -f "$METADATA_PATH" ]; then
    return 1
  fi
  python3 - "$METADATA_PATH" "$field" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
field = sys.argv[2]
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    sys.exit(1)
value = data.get(field)
if value is None:
    sys.exit(1)
print(value)
PY
}

run_existing_uninstall_if_needed() {
  local installed_grade installed_version

  if [ ! -f "$METADATA_PATH" ]; then
    return 0
  fi

  installed_grade="$(read_installed_metadata_field grade 2>/dev/null || true)"
  installed_version="$(read_installed_metadata_field version 2>/dev/null || true)"

  if [ "$installed_grade" = "$GRADE" ] && [ "$installed_version" = "$VERSION" ]; then
    log INFO "install metadata already matches target grade/version; skipping pre-install cleanup"
    return 0
  fi

  if [ ! -x "$CURRENT_UNINSTALL" ]; then
    die "installed metadata exists but current uninstall contract is missing: $CURRENT_UNINSTALL"
  fi

  log INFO "detected installed grade/version ($installed_grade/$installed_version) -> target ($GRADE/$VERSION); running current uninstall contract"
  bash "$CURRENT_UNINSTALL"
}

detect_os() {
  local uname_out
  uname_out="$(uname -s)"
  case "$uname_out" in
    Darwin) echo "macos" ;;
    Linux)
      if [ -r /etc/os-release ] && grep -qi '^ID=ubuntu' /etc/os-release; then
        echo "ubuntu"
      else
        echo "linux"
      fi
      ;;
    *) die "unsupported OS: $uname_out" ;;
  esac
}

run_privileged() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
    return 0
  fi

  die "requires root privileges but sudo is unavailable: $*"
}

apt_package_available() {
  local pkg="$1"
  apt-cache show "$pkg" >/dev/null 2>&1
}

install_apt_packages_if_available() {
  local pkg
  local available=()
  local missing=()

  for pkg in "$@"; do
    if apt_package_available "$pkg"; then
      available+=("$pkg")
    else
      missing+=("$pkg")
    fi
  done

  if [ "${#available[@]}" -gt 0 ]; then
    run_privileged apt-get install -y "${available[@]}"
  fi

  if [ "${#missing[@]}" -gt 0 ]; then
    log INFO "apt package not found (skipped): ${missing[*]}"
  fi
}

install_brew_formulas_best_effort() {
  local formula

  for formula in "$@"; do
    if brew list --formula "$formula" >/dev/null 2>&1; then
      continue
    fi
    if ! brew install "$formula"; then
      log INFO "brew install failed (skipped): $formula"
    fi
  done
}

prepend_path_if_missing() {
  local path_dir="$1"
  case ":$PATH:" in
    *":$path_dir:"*) ;;
    *) PATH="$path_dir:$PATH" ;;
  esac
}

resolve_brew_bin() {
  local candidate

  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return 0
  fi

  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

bootstrap_macos_homebrew_env() {
  local brew_bin

  if ! brew_bin="$(resolve_brew_bin)"; then
    die "Homebrew is required on macOS to bootstrap the shared-base toolchain"
  fi

  eval "$("$brew_bin" shellenv)"
  prepend_path_if_missing "$(dirname "$brew_bin")"
}

bootstrap_base_tools() {
  local os_target="$1"

  if [ "$os_target" = "ubuntu" ]; then
    run_privileged apt-get update
    run_privileged apt-get install -y make bash git curl jq tmux unzip
    install_apt_packages_if_available btop gh
    return 0
  fi

  if [ "$os_target" = "macos" ]; then
    bootstrap_macos_homebrew_env
    brew update
    install_brew_formulas_best_effort make bash git curl jq tmux unzip btop gh
    return 0
  fi

  log INFO "non-Ubuntu Linux detected; skipping package bootstrap and assuming prerequisites are managed externally"
}

ensure_starship_installed() {
  local os_target="$1"

  if command -v starship >/dev/null 2>&1; then
    return 0
  fi

  if [ "$os_target" = "macos" ]; then
    if brew install starship; then
      return 0
    fi
    log INFO "brew starship install failed; falling back to install script"
  fi

  curl -fsSL https://starship.rs/install.sh | sh -s -- -y
  command -v starship >/dev/null 2>&1 || die "failed to install starship"
}

ensure_uv_installed() {
  if command -v uv >/dev/null 2>&1 && command -v uvx >/dev/null 2>&1; then
    return 0
  fi

  prepend_path_if_missing "$HOME/.local/bin"
  command -v curl >/dev/null 2>&1 || die "curl is required to install uv/uvx"
  curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="$HOME/.local/bin" sh
  prepend_path_if_missing "$HOME/.local/bin"
  command -v uv >/dev/null 2>&1 || die "failed to install uv"
  command -v uvx >/dev/null 2>&1 || die "failed to install uvx"
}

ensure_bw_installed() {
  local os_target="$1"
  local arch target tag version download_url tmpdir

  prepend_path_if_missing "$HOME/.local/bin"
  if command -v bw >/dev/null 2>&1; then
    return 0
  fi

  command -v curl >/dev/null 2>&1 || die "curl is required to install Bitwarden CLI (bw)"
  command -v unzip >/dev/null 2>&1 || die "unzip is required to install Bitwarden CLI (bw)"

  case "$os_target" in
    ubuntu|linux) target="bw-linux" ;;
    macos) target="bw-macos" ;;
    *) die "unsupported OS for bw installation: $os_target" ;;
  esac

  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) ;;
    arm64|aarch64) target="${target}-arm64" ;;
    *) die "unsupported architecture for bw installation: $arch" ;;
  esac

  tag="$(curl -fsSL 'https://api.github.com/repos/bitwarden/clients/releases/latest' | jq -r '.tag_name')"
  [ -n "$tag" ] && [ "$tag" != "null" ] || die "failed to resolve latest Bitwarden CLI release"
  version="${tag#cli-v}"
  download_url="https://github.com/bitwarden/clients/releases/download/${tag}/${target}-${version}.zip"

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN
  curl -fsSL -o "$tmpdir/bw.zip" "$download_url"
  unzip -oq "$tmpdir/bw.zip" -d "$tmpdir"
  install -m 0755 "$tmpdir/bw" "$HOME/.local/bin/bw"
  command -v bw >/dev/null 2>&1 || die "failed to install Bitwarden CLI (bw)"
  rm -rf "$tmpdir"
  trap - RETURN
}

ensure_bws_installed() {
  local os_target="$1"
  local arch target version download_url tmpdir

  prepend_path_if_missing "$HOME/.local/bin"
  if command -v bws >/dev/null 2>&1; then
    return 0
  fi

  command -v curl >/dev/null 2>&1 || die "curl is required to install Bitwarden Secrets Manager CLI (bws)"
  command -v unzip >/dev/null 2>&1 || die "unzip is required to install Bitwarden Secrets Manager CLI (bws)"

  arch="$(uname -m)"
  case "$os_target:$arch" in
    ubuntu:x86_64|linux:x86_64|ubuntu:amd64|linux:amd64)
      target="bws-x86_64-unknown-linux-gnu"
      ;;
    ubuntu:aarch64|linux:aarch64|ubuntu:arm64|linux:arm64)
      target="bws-aarch64-unknown-linux-gnu"
      ;;
    macos:arm64|macos:aarch64)
    target="bws-macos-universal"
      ;;
    macos:x86_64|macos:amd64)
      target="bws-x86_64-apple-darwin"
      ;;
    *)
      die "unsupported OS/architecture for bws installation: $os_target/$arch"
      ;;
  esac

  version="$(curl -fsSL 'https://api.github.com/repos/bitwarden/sdk/releases?per_page=100' | jq -r '.[] | select(.tag_name | startswith("bws-v")) | .tag_name' | head -n 1)"
  [ -n "$version" ] && [ "$version" != "null" ] || die "failed to resolve latest bws release"
  download_url="https://github.com/bitwarden/sdk/releases/download/${version}/${target}-${version#bws-v}.zip"

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN
  curl -fsSL -o "$tmpdir/bws.zip" "$download_url"
  unzip -oq "$tmpdir/bws.zip" -d "$tmpdir"
  install -m 0755 "$tmpdir/bws" "$HOME/.local/bin/bws"
  command -v bws >/dev/null 2>&1 || die "failed to install Bitwarden Secrets Manager CLI (bws)"
  rm -rf "$tmpdir"
  trap - RETURN
}

ensure_tombi_installed() {
  if command -v tombi >/dev/null 2>&1; then
    return 0
  fi

  command -v curl >/dev/null 2>&1 || die "curl is required to install tombi"
  prepend_path_if_missing "$HOME/.local/bin"
  curl -fsSL https://tombi-toml.github.io/tombi/install.sh | sh -s -- --install-dir "$HOME/.local/bin"
  command -v tombi >/dev/null 2>&1 || die "failed to install tombi"
}

ensure_btop_installed() {
  local os_target="$1"
  local arch target tag version download_url tmpdir

  prepend_path_if_missing "$HOME/.local/bin"
  if command -v btop >/dev/null 2>&1; then
    return 0
  fi

  if [ "$os_target" = "macos" ]; then
    if brew install btop; then
      return 0
    fi
    die "failed to install btop with Homebrew"
  fi

  command -v curl >/dev/null 2>&1 || die "curl is required to install btop"
  command -v tar >/dev/null 2>&1 || die "tar is required to install btop"

  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) target="btop-x86_64-unknown-linux-musl" ;;
    aarch64|arm64) target="btop-aarch64-unknown-linux-musl" ;;
    *) die "unsupported architecture for btop installation: $arch" ;;
  esac

  tag="$(curl -fsSL 'https://api.github.com/repos/aristocratos/btop/releases/latest' | jq -r '.tag_name')"
  [ -n "$tag" ] && [ "$tag" != "null" ] || die "failed to resolve latest btop release"
  version="${tag#v}"
  download_url="https://github.com/aristocratos/btop/releases/download/${tag}/${target}.tbz"

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN
  curl -fsSL -o "$tmpdir/btop.tbz" "$download_url"
  tar -xjf "$tmpdir/btop.tbz" -C "$tmpdir"
  install -m 0755 "$tmpdir/btop/bin/btop" "$HOME/.local/bin/btop"
  command -v btop >/dev/null 2>&1 || die "failed to install btop ${version}"
  rm -rf "$tmpdir"
  trap - RETURN
}

ensure_gh_installed() {
  local os_target="$1"
  local arch tag version target download_url tmpdir extracted_root

  prepend_path_if_missing "$HOME/.local/bin"
  if command -v gh >/dev/null 2>&1; then
    return 0
  fi

  if [ "$os_target" = "macos" ]; then
    if brew install gh; then
      return 0
    fi
    die "failed to install gh with Homebrew"
  fi

  command -v curl >/dev/null 2>&1 || die "curl is required to install gh"
  command -v tar >/dev/null 2>&1 || die "tar is required to install gh"

  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) target="linux_amd64" ;;
    aarch64|arm64) target="linux_arm64" ;;
    *) die "unsupported architecture for gh installation: $arch" ;;
  esac

  tag="$(curl -fsSL 'https://api.github.com/repos/cli/cli/releases/latest' | jq -r '.tag_name')"
  [ -n "$tag" ] && [ "$tag" != "null" ] || die "failed to resolve latest gh release"
  version="${tag#v}"
  download_url="https://github.com/cli/cli/releases/download/${tag}/gh_${version}_${target}.tar.gz"

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN
  curl -fsSL -o "$tmpdir/gh.tar.gz" "$download_url"
  tar -xzf "$tmpdir/gh.tar.gz" -C "$tmpdir"
  extracted_root="$tmpdir/gh_${version}_${target}"
  install -m 0755 "$extracted_root/bin/gh" "$HOME/.local/bin/gh"
  command -v gh >/dev/null 2>&1 || die "failed to install gh ${version}"
  rm -rf "$tmpdir"
  trap - RETURN
}

ensure_required_shared_tools() {
  local missing=()

  command -v bash >/dev/null 2>&1 || missing+=("bash")
  command -v git >/dev/null 2>&1 || missing+=("git")
  command -v curl >/dev/null 2>&1 || missing+=("curl")
  command -v jq >/dev/null 2>&1 || missing+=("jq")
  command -v tmux >/dev/null 2>&1 || missing+=("tmux")
  command -v uv >/dev/null 2>&1 || missing+=("uv")
  command -v uvx >/dev/null 2>&1 || missing+=("uvx")
  command -v bw >/dev/null 2>&1 || missing+=("bw")
  command -v bws >/dev/null 2>&1 || missing+=("bws")
  command -v starship >/dev/null 2>&1 || missing+=("starship")
  command -v btop >/dev/null 2>&1 || missing+=("btop")
  command -v gh >/dev/null 2>&1 || missing+=("gh")
  command -v tombi >/dev/null 2>&1 || missing+=("tombi")

  if [ "${#missing[@]}" -gt 0 ]; then
    die "shared-base required tool(s) missing after bootstrap: ${missing[*]}"
  fi
}

ensure_tmux_catppuccin_installed() {
  local plugin_dir version

  plugin_dir="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/plugins/catppuccin/tmux"
  version="v2.1.3"
  if [ -f "$plugin_dir/catppuccin.tmux" ]; then
    return 0
  fi
  mkdir -p "$(dirname "$plugin_dir")"
  git clone -b "$version" https://github.com/catppuccin/tmux.git "$plugin_dir"
}

font_root_for_os() {
  local os_target="$1"
  case "$os_target" in
    ubuntu|linux) echo "$HOME/.local/share/fonts" ;;
    macos) echo "$HOME/Library/Fonts" ;;
    *) echo "$HOME/.local/share/fonts" ;;
  esac
}

macos_font_registry_has_name() {
  local font_name="$1"
  atsutil fonts -list 2>/dev/null | awk -v font_name="$font_name" '
    BEGIN { found = 0 }
    /^\{/ { next }
    {
      if (index($0, font_name) > 0) {
        found = 1
        exit 0
      }
    }
    END { exit(found ? 0 : 1) }
  '
}

macos_font_family_name_for_source_dir() {
  local source_dir_name="$1"
  case "$source_dir_name" in
    D2CodingLigature-Nerd-Font) printf '%s\n' 'D2CodingLigature Nerd Font' ;;
    Pretendard) printf '%s\n' 'Pretendard' ;;
    Pretendard-JP) printf '%s\n' 'Pretendard JP' ;;
    *) return 1 ;;
  esac
}

prune_legacy_macos_font_links() {
  local font_root="$1"
  local target_root="$font_root/jhoya"
  local target

  [ -d "$target_root" ] || return 0
  while IFS= read -r -d '' target; do
    remove_symlink_if_points_to_prefix "$target" "$REPO_ROOT/assets/fonts"
  done < <(find "$target_root" -type l -print0)
  find "$target_root" -depth -type d -empty -delete 2>/dev/null || true
}

install_macos_font_file() {
  local source="$1"
  local target="$2"

  if [ -f "$target" ] && [ ! -L "$target" ] && cmp -s "$source" "$target"; then
    log INFO "skip (already installed): $target"
    return 0
  fi

  if [ -e "$target" ] || [ -L "$target" ]; then
    rm -rf "$target"
    log INFO "removed existing path: $target"
  fi

  cp "$source" "$target"
  log INFO "installed $target from $source"
}

link_fonts() {
  local os_target="$1"
  local font_root="$2"
  local source_root="$REPO_ROOT/assets/fonts"
  local source_dir family target font_file macos_family_name

  [ -d "$source_root" ] || {
    log INFO "fonts source not found: $source_root (skipped)"
    return 0
  }

  if [ "$os_target" = "macos" ]; then
    prune_legacy_macos_font_links "$font_root"
    while IFS= read -r -d '' source_dir; do
      family="$(basename "$source_dir")"
      if ! macos_family_name="$(macos_font_family_name_for_source_dir "$family")"; then
        continue
      fi
      if macos_font_registry_has_name "$macos_family_name"; then
        log INFO "skip macOS font family already available: $macos_family_name"
        continue
      fi
      while IFS= read -r -d '' font_file; do
        target="$font_root/jhoya-dotfiles-$(basename "$font_file")"
        install_macos_font_file "$font_file" "$target"
      done < <(find "$source_dir" -maxdepth 1 -type f \( -name '*.ttf' -o -name '*.otf' \) -print0)
    done < <(find "$source_root" -mindepth 1 -maxdepth 1 -type d -print0)
    return 0
  fi

  mkdir -p "$font_root/jhoya"
  while IFS= read -r -d '' source_dir; do
    family="$(basename "$source_dir")"
    target="$font_root/jhoya/$family"
    ensure_symlink "$source_dir" "$target"
  done < <(find "$source_root" -mindepth 1 -maxdepth 1 -type d -print0)

  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$font_root/jhoya" >/dev/null 2>&1 || true
  fi
}

link_templates() {
  ensure_symlink "$REPO_ROOT/config/common/jhoya/.env.template" "$HOME/.config/jhoya/.env.template"
  ensure_symlink "$REPO_ROOT/config/common/jhoya/secrets/.env.template" "$HOME/.config/jhoya/secrets/.env.template"

  if [ ! -f "$HOME/.config/jhoya/.env" ]; then
    cp "$REPO_ROOT/config/common/jhoya/.env.template" "$HOME/.config/jhoya/.env"
    log INFO "created $HOME/.config/jhoya/.env from template"
  fi

  if [ ! -f "$HOME/.config/jhoya/secrets/env" ]; then
    cp "$REPO_ROOT/config/common/jhoya/secrets/.env.template" "$HOME/.config/jhoya/secrets/env"
    chmod 600 "$HOME/.config/jhoya/secrets/env"
    log INFO "created $HOME/.config/jhoya/secrets/env from template"
  fi
}

link_shell_configs_shared() {
  local file

  mkdir -p "$HOME/.config/jhoya/shared"

  for file in "$REPO_ROOT/config/common/shell"/*.sh; do
    ensure_symlink "$file" "$HOME/.config/jhoya/shared/$(basename "$file")"
  done

  for file in "$REPO_ROOT/config/common/bash/bashrc.d"/*.sh; do
    ensure_symlink "$file" "$HOME/.config/jhoya/bashrc.d/$(basename "$file")"
  done
}

remove_legacy_shell_handoff_blocks_shared() {
  remove_block "$HOME/.profile" '# >>> jhoya-dotfiles-login-zsh >>>' '# <<< jhoya-dotfiles-login-zsh <<<'
  remove_block "$HOME/.bash_login" '# >>> jhoya-dotfiles-login-zsh >>>' '# <<< jhoya-dotfiles-login-zsh <<<'
  remove_block "$HOME/.bash_profile" '# >>> jhoya-dotfiles-login-zsh >>>' '# <<< jhoya-dotfiles-login-zsh <<<'
  remove_block "$HOME/.profile" '# >>> jhoya-dotfiles-bash-login >>>' '# <<< jhoya-dotfiles-bash-login <<<'
  remove_block "$HOME/.bash_login" '# >>> jhoya-dotfiles-bash-login >>>' '# <<< jhoya-dotfiles-bash-login <<<'
  remove_block "$HOME/.bash_profile" '# >>> jhoya-dotfiles-bash-login >>>' '# <<< jhoya-dotfiles-bash-login <<<'
}

link_tool_configs_shared() {
  ensure_symlink "$REPO_ROOT/config/common/btop" "$HOME/.config/btop"
  ensure_symlink "$REPO_ROOT/config/common/gh/config.yml" "$HOME/.config/gh/config.yml"
}

link_starship_config_shared() {
  ensure_symlink "$REPO_ROOT/config/common/starship/starship.toml" "$HOME/.config/starship.toml"
}

link_tmux_config() {
  ensure_symlink "$REPO_ROOT/config/common/tmux/tmux.conf" "$HOME/.tmux.conf"
}

install_shell_loader_blocks_shared() {
  local bash_begin bash_end bash_block
  local bash_login_begin bash_login_end bash_login_block
  local file existing_bash_login_count
  bash_begin='# >>> jhoya-dotfiles >>>'
  bash_end='# <<< jhoya-dotfiles <<<'
  bash_block=$(cat <<'BLOCK'
# >>> jhoya-dotfiles >>>
if [ -d "$HOME/.config/jhoya/bashrc.d" ]; then
  for f in "$HOME"/.config/jhoya/bashrc.d/*.sh; do
    [ -r "$f" ] && . "$f"
  done
  unset f
fi
# <<< jhoya-dotfiles <<<
BLOCK
)

  bash_login_begin='# >>> jhoya-dotfiles-bash-login >>>'
  bash_login_end='# <<< jhoya-dotfiles-bash-login <<<'
  bash_login_block=$(cat <<'BLOCK'
# >>> jhoya-dotfiles-bash-login >>>
if [ -f ~/.bashrc ]; then
  . ~/.bashrc
fi
# <<< jhoya-dotfiles-bash-login <<<
BLOCK
)

  remove_legacy_shell_handoff_blocks_shared
  remove_block "$HOME/.zshrc" '# >>> jhoya-dotfiles >>>' '# <<< jhoya-dotfiles <<<'
  if [ ! -f "$HOME/.bashrc" ]; then
    touch "$HOME/.bashrc"
    log INFO "created $HOME/.bashrc for managed bash integration"
  fi
  add_block_once "$HOME/.bashrc" "$bash_begin" "$bash_end" "$bash_block"

  existing_bash_login_count=0
  for file in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
    if [ -f "$file" ]; then
      existing_bash_login_count=$((existing_bash_login_count + 1))
      ensure_bash_login_bridge "$file" "$bash_login_begin" "$bash_login_end" "$bash_login_block"
    fi
  done

  if [ "$existing_bash_login_count" -eq 0 ]; then
    ensure_bash_login_bridge "$HOME/.bash_profile" "$bash_login_begin" "$bash_login_end" "$bash_login_block"
  fi
}

write_install_metadata() {
  mkdir -p "$STATE_DIR" "$BIN_DIR"
  python3 - <<PY
import json
from pathlib import Path
path = Path(${METADATA_PATH@Q})
payload = {
    "grade": ${GRADE@Q},
    "version": ${VERSION@Q},
    "repo": "jhoya-dotfiles-shared",
    "mode": ${MODE@Q},
    "repo_root": ${REPO_ROOT@Q},
}
path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
}

install_current_uninstall_contract() {
  python3 - "$SCRIPT_DIR" "$CURRENT_UNINSTALL" <<'PY'
from pathlib import Path
import sys

script_dir = Path(sys.argv[1])
target_path = Path(sys.argv[2])
link_path = script_dir / "link.sh"
uninstall_path = script_dir / "uninstall.sh"

def strip_prelude(text: str) -> str:
    skip_prefixes = (
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        "SCRIPT_DIR=",
        "REPO_ROOT=",
        "STATE_DIR=",
        "BIN_DIR=",
        "METADATA_PATH=",
        "CURRENT_UNINSTALL=",
        "JHOYA_STATE_DIR=",
        "JHOYA_MANAGED_SYMLINKS_TMP=",
        "export JHOYA_STATE_DIR JHOYA_MANAGED_SYMLINKS_TMP",
        "source \"$SCRIPT_DIR/link.sh\"",
        "# shellcheck source=./link.sh",
    )
    kept = []
    for line in text.splitlines():
        if any(line.startswith(prefix) for prefix in skip_prefixes):
            continue
        kept.append(line)
    return "\n".join(kept).strip() + "\n"

link_body = strip_prelude(link_path.read_text(encoding="utf-8"))
uninstall_body = strip_prelude(uninstall_path.read_text(encoding="utf-8"))

content = f"""#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${{JHOYA_STATE_DIR:-$HOME/.config/jhoya/state}}"
BIN_DIR="${{XDG_CONFIG_HOME:-$HOME/.config}}/jhoya/bin"
METADATA_PATH="$STATE_DIR/install-metadata.json"
CURRENT_UNINSTALL="$BIN_DIR/uninstall-current-install.sh"
JHOYA_STATE_DIR="$STATE_DIR"
export JHOYA_STATE_DIR

{link_body}

{uninstall_body}"""

target_path.parent.mkdir(parents=True, exist_ok=True)
target_path.write_text(content, encoding="utf-8")
PY

  chmod 0755 "$CURRENT_UNINSTALL"
}

bootstrap_tools_and_plugins() {
  local os_target="$1"
  local skip_bootstrap="${JHOYA_SKIP_BOOTSTRAP:-0}"

  if [ "$skip_bootstrap" = "1" ]; then
    log INFO "JHOYA_SKIP_BOOTSTRAP=1; skipping shared-base tool bootstrap"
    return 0
  fi

  bootstrap_base_tools "$os_target"
  ensure_uv_installed
  ensure_bw_installed "$os_target"
  ensure_bws_installed "$os_target"
  ensure_tombi_installed
  ensure_starship_installed "$os_target"
  ensure_btop_installed "$os_target"
  ensure_gh_installed "$os_target"
  ensure_required_shared_tools
  ensure_tmux_catppuccin_installed
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

case "$MODE" in
  standalone) GRADE="remote" ;;
  private-overlay|overlay)
    GRADE="private"
    MANAGES_INSTALL_CONTRACT=0
    ;;
  *) die "unsupported install mode: $MODE" ;;
esac

OS_TARGET="$(detect_os)"
if [ "$MANAGES_INSTALL_CONTRACT" = "1" ]; then
  run_existing_uninstall_if_needed
  manifest_reset_tmp
fi
bootstrap_tools_and_plugins "$OS_TARGET"
link_shell_configs_shared
link_fonts "$OS_TARGET" "$(font_root_for_os "$OS_TARGET")"
link_templates
link_tmux_config
link_tool_configs_shared
link_starship_config_shared
install_shell_loader_blocks_shared
if [ "$MANAGES_INSTALL_CONTRACT" = "1" ]; then
  manifest_finalize
  write_install_metadata
  install_current_uninstall_contract
  printf '%s\n' '[jhoya-dotfiles-shared] install contract initialized.'
  printf 'mode=%s grade=%s version=%s os=%s\n' "$MODE" "$GRADE" "$VERSION" "$OS_TARGET"
else
  printf '%s\n' '[jhoya-dotfiles-shared] overlay component refreshed.'
  printf 'mode=%s grade=%s version=%s os=%s\n' "$MODE" "$GRADE" "$VERSION" "$OS_TARGET"
fi
