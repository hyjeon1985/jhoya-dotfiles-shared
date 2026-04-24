#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${JHOYA_ENV_FILE:-$HOME/.config/jhoya/.env}"
TEMPLATE_FILE="${JHOYA_ENV_TEMPLATE_FILE:-$HOME/.config/jhoya/.env.template}"

log() {
  printf '[%s] %s\n' "$1" "$2"
}

die() {
  log ERROR "$1" >&2
  exit 1
}

command -v gh >/dev/null 2>&1 || die "gh CLI가 필요합니다."
gh auth status >/dev/null 2>&1 || die "gh auth login 상태가 필요합니다."

gh_login="$(gh api user --jq '.login' 2>/dev/null || true)"
gh_id="$(gh api user --jq '.id' 2>/dev/null || true)"
gh_name="$(gh api user --jq '.name' 2>/dev/null || true)"

[ -n "$gh_login" ] || die "GitHub login을 확인하지 못했습니다."
[ -n "$gh_id" ] || die "GitHub numeric id를 확인하지 못했습니다."

if [ -z "$gh_name" ] || [ "$gh_name" = "null" ]; then
  gh_name="$gh_login"
fi

gh_noreply="${gh_id}+${gh_login}@users.noreply.github.com"

mkdir -p "$(dirname "$ENV_FILE")"

if [ ! -f "$ENV_FILE" ]; then
  if [ -f "$TEMPLATE_FILE" ]; then
    cp "$TEMPLATE_FILE" "$ENV_FILE"
    log INFO "$ENV_FILE 파일을 template에서 생성했습니다."
  else
    : > "$ENV_FILE"
    log INFO "$ENV_FILE 파일을 새로 생성했습니다."
  fi
fi

tmp_file="$(mktemp)"
grep -Ev '^[[:space:]]*(export[[:space:]]+)?GIT_(NAME|EMAIL)=' "$ENV_FILE" > "$tmp_file" || true
printf '%s\n' "export GIT_NAME=\"$gh_name\"" >> "$tmp_file"
printf '%s\n' "export GIT_EMAIL=\"$gh_noreply\"" >> "$tmp_file"
mv "$tmp_file" "$ENV_FILE"

git config --global user.name "$gh_name"
git config --global user.email "$gh_noreply"

log INFO "GitHub 프로필 기준으로 git identity를 갱신했습니다."
printf '  GIT_NAME=%s\n' "$gh_name"
printf '  GIT_EMAIL=%s\n' "$gh_noreply"
