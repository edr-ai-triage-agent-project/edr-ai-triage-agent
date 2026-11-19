#!/usr/bin/env bash
set -euo pipefail
set +x

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

python3 - "$ROOT" <<'PY'
import json
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote

from dotenv import dotenv_values

root = Path(sys.argv[1])
local = dotenv_values(root / ".env")
server = dotenv_values(root / ".env.k8s")

api_key = local.get("OPENAI_API_KEY")
password = server.get("POSTGRES_PASSWORD")

if not api_key or not password:
    raise SystemExit("OPENAI_API_KEY 또는 POSTGRES_PASSWORD가 없습니다.")

dsn = f"postgresql://soc:{quote(password, safe='')}@postgres:5432/soc"

manifest = {
    "apiVersion": "v1",
    "kind": "Secret",
    "metadata": {
        "name": "soc-secrets",
        "namespace": "soc",
    },
    "type": "Opaque",
    "stringData": {
        "OPENAI_API_KEY": api_key,
        "POSTGRES_PASSWORD": password,
        "POSTGRES_DSN": dsn,
    },
}

subprocess.run(
    [
        "ssh",
        "edr-team7",
        "sudo k3s kubectl -n soc apply -f -",
    ],
    input=json.dumps(manifest),
    text=True,
    check=True,
)

print("Secret 적용 완료 (비밀값은 출력하지 않음)")
PY
