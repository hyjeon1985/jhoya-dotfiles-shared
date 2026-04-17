#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${JHOYA_STATE_DIR:-$HOME/.config/jhoya/state}"
BIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/jhoya/bin"
METADATA_PATH="$STATE_DIR/install-metadata.json"
CURRENT_UNINSTALL="$BIN_DIR/uninstall-current-install.sh"

remove_manifest_managed_symlinks() {
  local manifest target source
  manifest="$(manifest_file)"
  [ -f "$manifest" ] || return 0

  while IFS=$'\t' read -r target source; do
    [ -n "$target" ] || continue
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
      rm -f "$target"
      log INFO "removed manifest-managed link: $target"
    fi
  done < "$manifest"

  rm -f "$manifest"
}

remove_fonts() {
  local target root

  if [ -d "$HOME/Library/Fonts" ]; then
    while IFS= read -r -d '' target; do
      rm -f "$target"
      log INFO "removed managed font file: $target"
    done < <(find "$HOME/Library/Fonts" -maxdepth 1 \( -type f -o -type l \) \( -name 'jhoya-dotfiles-*.ttf' -o -name 'jhoya-dotfiles-*.otf' \) -print0)
  fi

  for root in "$HOME/.local/share/fonts/jhoya" "$HOME/Library/Fonts/jhoya"; do
    [ -d "$root" ] || continue
    find "$root" -depth -type d -empty -delete 2>/dev/null || true
  done
}

remove_manifest_managed_symlinks
remove_fonts
remove_block "$HOME/.zshrc" '# >>> jhoya-dotfiles >>>' '# <<< jhoya-dotfiles <<<'
remove_block "$HOME/.bashrc" '# >>> jhoya-dotfiles >>>' '# <<< jhoya-dotfiles <<<'
remove_block "$HOME/.profile" '# >>> jhoya-dotfiles-login-zsh >>>' '# <<< jhoya-dotfiles-login-zsh <<<'
remove_block "$HOME/.bash_login" '# >>> jhoya-dotfiles-login-zsh >>>' '# <<< jhoya-dotfiles-login-zsh <<<'
remove_block "$HOME/.bash_profile" '# >>> jhoya-dotfiles-login-zsh >>>' '# <<< jhoya-dotfiles-login-zsh <<<'
remove_block "$HOME/.profile" '# >>> jhoya-dotfiles-bash-login >>>' '# <<< jhoya-dotfiles-bash-login <<<'
remove_block "$HOME/.bash_login" '# >>> jhoya-dotfiles-bash-login >>>' '# <<< jhoya-dotfiles-bash-login <<<'
remove_block "$HOME/.bash_profile" '# >>> jhoya-dotfiles-bash-login >>>' '# <<< jhoya-dotfiles-bash-login <<<'
rm -f "$METADATA_PATH"
rm -f "$CURRENT_UNINSTALL"
printf '%s\n' '[jhoya-dotfiles-shared] install contract cleaned.'
