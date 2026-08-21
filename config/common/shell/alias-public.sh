alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# --- mo (마크다운 뷰어) ---------------------------------------------------
# mo 는 등록 시점에 글롭을 펼쳐 파일 목록을 들고 있고, 그 뒤 새로 생긴 파일과
# 워크트리를 감시가 간헐적으로만 잡는다(2026-08-21 실측). 그래서 다시 훑는
# 수단이 필요하다.
#
#   mo-refresh  다시 훑어 **더한다**. 사라진 경로는 남는다
#   mo-rebuild  현재 등록을 뜬 뒤 비우고 그대로 다시 건다. 사라진 것까지 맞춘다
mo-refresh() { mo --restart -p "${1:-${MO_PORT:-6275}}"; }

mo-rebuild() {
  _mo_port="${1:-${MO_PORT:-6275}}"
  _mo_plan=$(mo --status --json 2>/dev/null | python3 -c '
import json,sys
port=sys.argv[1]
for srv in json.load(sys.stdin):
    if not srv.get("url","").endswith(":"+port): continue
    for g in srv.get("groups") or []:
        pats=" ".join("\x27%s\x27" % p for p in g.get("patterns") or [])
        if pats: print("mo %s -w --no-open --target %s --port %s" % (pats, g["name"], port))
' "$_mo_port") || { echo "mo-rebuild: 등록 상태를 뜨지 못했다" >&2; return 1; }

  [ -n "$_mo_plan" ] || { echo "mo-rebuild: 포트 $_mo_port 에 등록된 그룹이 없다" >&2; return 1; }

  printf '%s\n' "$_mo_plan" | sed 's/^/  /'
  printf 'mo-rebuild: 위 %s개 그룹으로 다시 건다. 진행? [y/N] ' "$(printf '%s\n' "$_mo_plan" | wc -l | tr -d ' ')"
  read -r _mo_ans
  case "$_mo_ans" in [yY]*) ;; *) echo "취소했다"; return 1 ;; esac

  echo y | mo --clear --port "$_mo_port" >/dev/null 2>&1
  # mo 는 stdin 으로 마크다운을 받으므로 파이프를 물려주면 안 된다
  printf '%s\n' "$_mo_plan" | while IFS= read -r _mo_cmd; do
    eval "$_mo_cmd" </dev/null >/dev/null 2>&1
  done
  mo --status --json 2>/dev/null | python3 -c '
import json,sys
port=sys.argv[1]
for srv in json.load(sys.stdin):
    if srv.get("url","").endswith(":"+port):
        for g in srv.get("groups") or []: print("  %-32s %s files" % (g["name"], g["files"]))
' "$_mo_port"
  unset _mo_port _mo_plan _mo_ans _mo_cmd
}
