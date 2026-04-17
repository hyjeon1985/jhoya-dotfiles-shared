export COLORTERM="${COLORTERM:-truecolor}"

if [ -z "${TMUX:-}" ]; then
  export TERM="${TERM:-xterm-256color}"
fi

export JHOYA_FONT_MONO="${JHOYA_FONT_MONO:-D2CodingLigature Nerd Font}"
export JHOYA_FONT_UI="${JHOYA_FONT_UI:-Pretendard}"
export JHOYA_FONT_KO="${JHOYA_FONT_KO:-Pretendard}"
export JHOYA_WEZTERM_FONT_SIZE="${JHOYA_WEZTERM_FONT_SIZE:-14.0}"

wtitle() {
  printf '\033]2;%s\007' "@jhoya:$*"
}

wtitle-clear() {
  printf '\033]2;%s\007' '@jhoya:auto'
}
