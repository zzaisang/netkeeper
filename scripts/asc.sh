#!/usr/bin/env bash
# App Store Connect API 도우미. 절차는 .claude/skills/asc-submit/SKILL.md.
#
# 사용:
#   scripts/asc.sh GET  'apps/$ASC_APP_ID/appStoreVersions?limit=3'
#   scripts/asc.sh POST reviewSubmissions '{"data":{...}}'
#   scripts/asc.sh PATCH appStoreVersions/<id> @body.json
#   scripts/asc.sh DELETE appScreenshots/<id>
#   scripts/asc.sh upload-screenshots <appScreenshotSetId> <png-dir>   # 기존 장 삭제 후 이름순 업로드
#
# - 키: ~/.appstoreconnect/netkeeper.env (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH). .p8 은 경로로만 쓰고
#   JWT 와 키 내용은 출력하지 않는다. JWT 는 호출마다 새로 만든다(20분 만료).
# - 응답 JSON 은 stdout 으로 그대로 나온다. 4xx/5xx 면 errors 요약을 stderr 에 쓰고 exit 1.
set -euo pipefail

ENV_FILE=${ASC_ENV_FILE:-$HOME/.appstoreconnect/netkeeper.env}
[[ -f $ENV_FILE ]] || { echo "ERROR: $ENV_FILE 없음" >&2; exit 65; }
# shellcheck disable=SC1090
source "$ENV_FILE"
BASE=https://api.appstoreconnect.apple.com/v1

jwt() {
  xcrun altool --generate-jwt --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 |
    grep -oE 'eyJ[A-Za-z0-9._-]+' | head -1
}

call() { # method path [body|@file]
  local m=$1 p=$2 body=${3:-} tok out code
  tok=$(jwt)
  [[ -n $tok ]] || { echo "ERROR: JWT 생성 실패 (키 경로·ID 확인)" >&2; exit 1; }
  out=$(mktemp)
  local args=(-sS -m 120 -X "$m" -o "$out" -w '%{http_code}'
    -H "Authorization: Bearer $tok" -H 'Content-Type: application/json')
  [[ -n $body ]] && args+=(--data-binary "$body")
  code=$(curl "${args[@]}" "$BASE/${p#/}")
  cat "$out"
  if [[ $code -ge 400 ]]; then
    python3 - "$out" "$code" >&2 <<'EOF'
import json, sys
try: d = json.load(open(sys.argv[1]))
except Exception: d = {}
print(f"HTTP {sys.argv[2]}")
for e in d.get('errors', []):
    print(' ', e.get('code'), '-', e.get('detail'))
    for k, v in ((e.get('meta') or {}).get('associatedErrors') or {}).items():
        for x in v: print('    ', k, x.get('code'), '-', x.get('detail'))
EOF
    rm -f "$out"; exit 1
  fi
  rm -f "$out"
}

upload_screenshots() { # setId dir
  local set=$1 dir=$2
  [[ -d $dir ]] || { echo "ERROR: $dir 없음" >&2; exit 65; }
  call GET "appScreenshotSets/$set/appScreenshots?limit=50" |
    python3 -c 'import json,sys;[print(x["id"]) for x in json.load(sys.stdin).get("data",[])]' |
    while read -r id; do call DELETE "appScreenshots/$id" >/dev/null; echo "deleted $id"; done
  local f size sid resp
  for f in $(ls "$dir"/*.png | sort); do
    size=$(stat -f%z "$f")
    resp=$(call POST appScreenshots "$(python3 -c '
import json,sys
print(json.dumps({"data":{"type":"appScreenshots","attributes":{"fileName":sys.argv[1],"fileSize":int(sys.argv[2])},
 "relationships":{"appScreenshotSet":{"data":{"type":"appScreenshotSets","id":sys.argv[3]}}}}}))' "$(basename "$f")" "$size" "$set")")
    sid=$(python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["id"])' <<<"$resp")
    # uploadOperations: 파일 조각을 지정된 URL 로 PUT
    local rf; rf=$(mktemp); printf '%s' "$resp" > "$rf"
    python3 - "$f" "$rf" <<'EOF'
import json, subprocess, sys
d = json.load(open(sys.argv[2])); data = open(sys.argv[1], 'rb').read()
for op in d['data']['attributes']['uploadOperations']:
    cmd = ['curl', '-sS', '-m', '120', '-X', op['method'], op['url'], '--data-binary', '@-', '-o', '/dev/null', '-w', '%{http_code}']
    for h in op['requestHeaders']: cmd += ['-H', f"{h['name']}: {h['value']}"]
    r = subprocess.run(cmd, input=data[op['offset']:op['offset'] + op['length']], capture_output=True)
    if not r.stdout.decode().startswith('2'): sys.exit(f"upload part failed: {r.stdout.decode()} {r.stderr.decode()[:200]}")
EOF
    rm -f "$rf"
    call PATCH "appScreenshots/$sid" "$(python3 -c '
import json,sys,hashlib
print(json.dumps({"data":{"type":"appScreenshots","id":sys.argv[1],"attributes":{"uploaded":True,
 "sourceFileChecksum":hashlib.md5(open(sys.argv[2],"rb").read()).hexdigest()}}}))' "$sid" "$f")" >/dev/null
    echo "uploaded $(basename "$f") -> $sid"
  done
}

case ${1:-} in
  GET|DELETE) call "$1" "$2" ;;
  POST|PATCH)
    b=${3:-}; [[ $b == @* ]] && b=$(cat "${b#@}")
    call "$1" "$2" "$b" ;;
  upload-screenshots) upload_screenshots "$2" "$3" ;;
  *) sed -n '2,13p' "$0" >&2; exit 64 ;;
esac
