#!/usr/bin/env bash
# test-check-auto-build.sh — check-auto-build.sh 策略冒烟测试（mock curl）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fail=0
check() {
  if [ "$2" = "$3" ]; then echo "OK  $1"
  else echo "FAIL $1: got=[$2] want=[$3]" >&2; fail=1
  fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# mock curl: first call = upstream list; later = per-tag release
cat > "$WORK/curl" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
url="${@: -1}"
mkdir -p "$MOCK_DIR/calls"
echo "$url" >> "$MOCK_DIR/calls/log"
if [[ "$url" == *"/SagerNet/sing-box/releases?"* ]]; then
  cat "$MOCK_DIR/upstream.json"
  exit 0
fi
# download to -o file when present
out=""
prev=""
for a in "$@"; do
  if [ "$prev" = "-o" ]; then out="$a"; fi
  prev="$a"
done
tag=$(printf '%s' "$url" | sed -n 's|.*/releases/tags/v||p')
case "$tag" in
  1.14.0)
    body='{"assets":[{"name":"sing-box-1.14.0.tipa"}]}'
    code=200
    ;;
  1.14.0-rc.5)
    body='{"assets":[{"name":"sing-box-1.14.0-rc.5.tipa"}]}'
    code=200
    ;;
  1.14.0-rc.4)
    body='{"assets":[{"name":"a.tipa"},{"name":"a.apk"},{"name":"b.apk"}]}'
    code=200
    ;;
  *)
    body='{"message":"Not Found"}'
    code=404
    ;;
esac
if [ -n "$out" ]; then
  printf '%s' "$body" > "$out"
  # emulate curl -w %{http_code} on stdout only the code when -o used... 
  # our script uses -o file -w %{http_code} and captures CODE from stdout
fi
# If -w http_code requested, print code (script reads CODE from curl stdout with -o)
for a in "$@"; do
  if [ "$a" = "%{http_code}" ] || [ "$a" = "-w" ]; then :; fi
done
if printf '%s' "$*" | grep -q '%{http_code}'; then
  printf '%s' "$code"
else
  printf '%s' "$body"
fi
EOS
chmod +x "$WORK/curl"

cat > "$WORK/upstream.json" <<'JSON'
[
  {"tag_name":"v1.14.0","prerelease":false},
  {"tag_name":"v1.14.0-rc.5","prerelease":true},
  {"tag_name":"v1.13.21","prerelease":false},
  {"tag_name":"v1.14.0-rc.4","prerelease":true},
  {"tag_name":"v1.13.20","prerelease":false}
]
JSON

export PATH="$WORK:$PATH"
export MOCK_DIR="$WORK"
export GH_TOKEN=dummy
export GITHUB_REPOSITORY=largerthanlife/sing-box-for-ios
export GITHUB_OUTPUT="$WORK/out-apk.txt"
: > "$GITHUB_OUTPUT"

bash "$SCRIPT_DIR/check-auto-build.sh" apk > "$WORK/apk.log"
check "apk should_build" "$(grep '^should_build=' "$WORK/out-apk.txt" | cut -d= -f2)" "true"
check "apk queues 1.14.0" "$(grep -c '"tag":"1.14.0"' "$WORK/out-apk.txt" || true)" "1"
check "apk queues rc.5" "$(grep -c '"tag":"1.14.0-rc.5"' "$WORK/out-apk.txt" || true)" "1"
check "apk skips old no-release" "$(grep -c '1.13.21' "$WORK/out-apk.txt" || true)" "0"
check "apk skips rc.4 has apk" "$(grep -c 'rc.4' "$WORK/out-apk.txt" || true)" "0"

export GITHUB_OUTPUT="$WORK/out-tipa.txt"
: > "$GITHUB_OUTPUT"
bash "$SCRIPT_DIR/check-auto-build.sh" tipa > "$WORK/tipa.log"
check "tipa should_build false when tipas present" \
  "$(grep '^should_build=' "$WORK/out-tipa.txt" | cut -d= -f2)" "false"
check "tipa does not open 1.13.x" "$(grep -c '1.13' "$WORK/out-tipa.txt" || true)" "0"

check "script executable kind guard" \
  "$(bash "$SCRIPT_DIR/check-auto-build.sh" 2>&1 | head -1 | grep -c usage || true)" "1"

if [ "$fail" -ne 0 ]; then
  echo '---- apk log ----'; cat "$WORK/apk.log"
  echo '---- tipa log ----'; cat "$WORK/tipa.log"
  exit 1
fi
echo "all check-auto-build smoke tests passed"
