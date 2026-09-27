#!/usr/bin/env bash
set -euo pipefail
instance_id=$(terraform -chdir=infra output -raw instance_id)
: "${AWS_REGION:?}"
mkdir -p .artifacts
pids=()
cleanup() {
  for log in .artifacts/tunnel-*.log; do
    [[ -f "$log" ]] || continue
    session_id=$(sed -n 's/.*Starting session with SessionId: \([^[:space:]]*\).*/\1/p' "$log" | head -1)
    if [[ -n "$session_id" ]]; then
      aws ssm terminate-session --region "$AWS_REGION" --session-id "$session_id" >/dev/null || true
    fi
  done
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
}
trap cleanup EXIT
for port in 20157 30157 20158; do
  aws ssm start-session --region "$AWS_REGION" --target "$instance_id" \
    --document-name AWS-StartPortForwardingSession \
    --parameters "{\"portNumber\":[\"$port\"],\"localPortNumber\":[\"$port\"]}" \
    > ".artifacts/tunnel-$port.log" 2>&1 &
  pids+=("$!")
done
check() {
  local name=$1 url=$2
  for attempt in $(seq 1 30); do
    if curl --fail --silent --show-error --max-time 5 "$url" > ".artifacts/$name.json" 2>/dev/null; then return; fi
    sleep 2
  done
  echo "Endpoint did not become available: $url" >&2
  return 1
}
check vaultwarden http://localhost:20157/alive
check kuma http://localhost:30157/api/status-page/portfolio
check grafana http://localhost:20158/api/health
python3 - <<'PY'
import json
from datetime import datetime
from pathlib import Path

def read(name):
    return json.loads(Path(f'.artifacts/{name}.json').read_text())
datetime.fromisoformat(read('vaultwarden').replace('Z', '+00:00'))
assert read('grafana')['database'] == 'ok'
assert read('kuma')['config']['slug'] == 'portfolio'
assert len(read('kuma')['publicGroupList'][0]['monitorList']) == 4
print('All three application APIs passed curl and JSON checks through SSM tunnels.')
PY
