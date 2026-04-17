# shellcheck shell=sh
export PATH="$HOME/.local/bin:$PATH"

JHOYA_CONFIG_HOME="${JHOYA_CONFIG_HOME:-$HOME/.config/jhoya}"
export JHOYA_CONFIG_HOME

[ -f "$JHOYA_CONFIG_HOME/.env" ] && . "$JHOYA_CONFIG_HOME/.env"
[ -f "$JHOYA_CONFIG_HOME/secrets/env" ] && . "$JHOYA_CONFIG_HOME/secrets/env"

if [ -d "$JHOYA_CONFIG_HOME/local" ]; then
  for f in "$JHOYA_CONFIG_HOME"/local/*.sh; do
    [ -r "$f" ] && . "$f"
  done
  unset f
fi
