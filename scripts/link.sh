#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[%s] %s\n' "$1" "$2"
}

manifest_dir() {
  printf '%s' "${JHOYA_STATE_DIR:-$HOME/.config/jhoya/state}"
}

manifest_file() {
  printf '%s' "$(manifest_dir)/managed-symlinks.tsv"
}

manifest_tmp_file() {
  printf '%s' "${JHOYA_MANAGED_SYMLINKS_TMP:-$(manifest_dir)/managed-symlinks.next.tsv}"
}

manifest_ensure_parent() {
  mkdir -p "$(manifest_dir)"
}

manifest_reset_tmp() {
  manifest_ensure_parent
  : > "$(manifest_tmp_file)"
}

manifest_record_symlink() {
  local target="$1"
  local source="$2"
  manifest_ensure_parent
  printf '%s\t%s\n' "$target" "$source" >> "$(manifest_tmp_file)"
}

manifest_has_target() {
  local target="$1"
  local file
  file="$(manifest_file)"
  [ -f "$file" ] || return 1
  awk -F '\t' -v target="$target" '$1 == target { found = 1 } END { exit(found ? 0 : 1) }' "$file"
}

manifest_stale_targets() {
  local prev curr
  prev="$(manifest_file)"
  curr="$(manifest_tmp_file)"
  [ -f "$prev" ] || return 0
  [ -f "$curr" ] || return 0
  awk -F '\t' 'NR==FNR { keep[$1]=1; next } !($1 in keep) { print $1 "\t" $2 }' "$curr" "$prev"
}

manifest_finalize() {
  local prev curr target source
  prev="$(manifest_file)"
  curr="$(manifest_tmp_file)"
  manifest_ensure_parent

  if [ -f "$prev" ] && [ -f "$curr" ]; then
    while IFS=$'\t' read -r target source; do
      [ -n "$target" ] || continue
      if [ -L "$target" ]; then
        if [ "$(readlink "$target")" = "$source" ]; then
          rm -f "$target"
          log INFO "removed stale managed link: $target"
        fi
      fi
    done < <(manifest_stale_targets)
  fi

  mv "$curr" "$prev"
}

remove_existing_path() {
  local target="$1"

  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    return 0
  fi

  rm -rf "$target"
  log INFO "removed existing path: $target"
}

ensure_symlink() {
  local source="$1"
  local target="$2"
  local current_link
  local target_dir target_base temp_target

  if [ -L "$target" ]; then
    current_link="$(readlink "$target")"
    if [ "$current_link" = "$source" ]; then
      manifest_record_symlink "$target" "$source"
      log INFO "skip (already linked): $target"
      return 0
    fi
  fi

  if [ -d "$target" ] && [ ! -L "$target" ]; then
    remove_existing_path "$target"
  fi

  target_dir="$(dirname "$target")"
  target_base="$(basename "$target")"
  mkdir -p "$target_dir"

  if [ -e "$target" ] || [ -L "$target" ]; then
    temp_target="$(mktemp "$target_dir/.${target_base}.tmp.XXXXXX")"
    rm -f "$temp_target"
    ln -s "$source" "$temp_target"
    mv -f "$temp_target" "$target"
  else
    ln -s "$source" "$target"
  fi

  manifest_record_symlink "$target" "$source"
  log INFO "linked $target -> $source"
}

remove_symlink_if_points_to_prefix() {
  local target="$1"
  local prefix="$2"
  local link_target

  if [ ! -L "$target" ]; then
    return 0
  fi

  link_target="$(readlink "$target")"
  case "$link_target" in
    "$prefix"/*)
      rm "$target"
      log INFO "removed link: $target"
      ;;
    *)
      log INFO "skip (not managed): $target"
      ;;
  esac
}

add_block_once() {
  local file="$1"
  local begin_marker="$2"
  local end_marker="$3"
  local block_content="$4"
  local tmp

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if grep -Fq "$begin_marker" "$file"; then
    local line skip
    tmp="$(mktemp)"
    skip=0

    while IFS= read -r line || [ -n "$line" ]; do
      if [ "$skip" -eq 1 ]; then
        if [ "$line" = "$end_marker" ]; then
          skip=0
        fi
        continue
      fi

      if [ "$line" = "$begin_marker" ]; then
        printf '%s\n' "$block_content" >> "$tmp"
        skip=1
        continue
      fi

      printf '%s\n' "$line" >> "$tmp"
    done < "$file"

    if cmp -s "$file" "$tmp"; then
      rm -f "$tmp"
      log INFO "block already up to date in $file"
      return 0
    fi

    mv "$tmp" "$file"
    log INFO "updated managed block in $file"
    return 0
  fi

  {
    [ -s "$file" ] && printf '\n'
    printf '%s\n' "$block_content"
  } >> "$file"

  log INFO "installed managed block into $file"
}

file_sources_bashrc() {
  local file="$1"

  if [ ! -f "$file" ]; then
    return 1
  fi

  grep -Eq '(^|[;&[:space:]])(\.|source)[[:space:]]+["'"'"']?([^"'"'"'[:space:]]*/)?\.bashrc["'"'"']?([;&[:space:]]|$)' "$file"
}

ensure_bash_login_bridge() {
  local file="$1"
  local begin_marker="$2"
  local end_marker="$3"
  local block_content="$4"

  if [ ! -f "$file" ]; then
    touch "$file"
    log INFO "created $file for managed bash login integration"
  fi

  if grep -Fq "$begin_marker" "$file"; then
    add_block_once "$file" "$begin_marker" "$end_marker" "$block_content"
    return 0
  fi

  if file_sources_bashrc "$file"; then
    log INFO "skip (existing bashrc trigger): $file"
    return 0
  fi

  add_block_once "$file" "$begin_marker" "$end_marker" "$block_content"
}

remove_block() {
  local file="$1"
  local begin_marker="$2"
  local end_marker="$3"
  local tmp

  if [ ! -f "$file" ]; then
    return 0
  fi

  tmp="$(mktemp)"
  awk -v begin="$begin_marker" -v end="$end_marker" '
    $0 == begin {skip = 1; next}
    $0 == end {skip = 0; next}
    !skip {print}
  ' "$file" > "$tmp"

  if cmp -s "$file" "$tmp"; then
    rm -f "$tmp"
    log INFO "no managed block found in $file"
    return 0
  fi

  mv "$tmp" "$file"
  log INFO "removed managed block from $file"
}
