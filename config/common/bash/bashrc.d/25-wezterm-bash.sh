# WezTerm shell integration / OSC 7 cwd reporting.
# Prefer the official integration when available; otherwise emit a minimal
# OSC 7 sequence so WezTerm can track the current directory even across ssh.

case $- in
  *i*) ;;
  *) return 0 ;;
esac

if [ -z "${__jhoya_wezterm_integration_loaded:-}" ]; then
  __jhoya_wezterm_integration_loaded=1
  export __jhoya_wezterm_integration_loaded
  __jhoya_restore_nounset=0
  case $- in
    *u*) __jhoya_restore_nounset=1 ;;
  esac

  if [ -r "/Applications/WezTerm.app/Contents/Resources/wezterm.sh" ]; then
    set +u
    . "/Applications/WezTerm.app/Contents/Resources/wezterm.sh"
    if [ "$__jhoya_restore_nounset" -eq 1 ]; then
      set -u
    fi
  elif [ -r "$HOME/Applications/WezTerm.app/Contents/Resources/wezterm.sh" ]; then
    set +u
    . "$HOME/Applications/WezTerm.app/Contents/Resources/wezterm.sh"
    if [ "$__jhoya_restore_nounset" -eq 1 ]; then
      set -u
    fi
  else
    __jhoya_emit_osc7() {
      local host
      host="${WEZTERM_HOSTNAME:-${HOSTNAME:-}}"
      if [ -z "$host" ]; then
        host="$(hostname 2>/dev/null || uname -n 2>/dev/null || printf '%s' localhost)"
      fi
      printf '\033]7;file://%s%s\033\\' "$host" "$PWD"
    }

    case ";${PROMPT_COMMAND:-};" in
      *";__jhoya_emit_osc7;"*) ;;
      *) PROMPT_COMMAND="__jhoya_emit_osc7${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
    esac
    export PROMPT_COMMAND
  fi
  unset __jhoya_restore_nounset
fi
