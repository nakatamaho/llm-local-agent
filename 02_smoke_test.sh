#!/usr/bin/env bash
# scripts/02_smoke_test.sh
# Verify inference server API works correctly
set -euo pipefail

INFERENCE_HOST="${1:-localhost}"
INFERENCE_PORT="${2:-8080}"
BASE_URL="http://${INFERENCE_HOST}:${INFERENCE_PORT}"

echo "=== Smoke Test: $BASE_URL ==="

# NOTE: llama-server exposes /v1/chat/completions (OpenAI-compatible)
# but the container uses internal network. From host, you need to
# either expose the port (add ports: in compose) or run via docker exec.
# This script is intended to run FROM INSIDE the network:
#   docker compose run --rm agent bash -c "curl http://172.30.0.10:8080/health"
# OR expose port temporarily:
#   docker compose exec inference curl http://localhost:8080/health

echo "[1/3] Health check..."
curl -sf "${BASE_URL}/health" | python3 -m json.tool
echo ""

echo "[2/3] Model info..."
curl -sf "${BASE_URL}/v1/models" | python3 -m json.tool
echo ""

echo "[3/3] Simple completion test..."
curl -s "${BASE_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer dummy-local-no-auth" \
  -d '{
    "model": "Qwen3.5-35B-A3B",
    "messages": [
      {"role": "system", "content": "You are a coding assistant. Be concise."},
      {"role": "user", "content": "Write a one-line Python function to compute factorial."}
    ],
    "max_tokens": 100,
    "temperature": 0.4,
    "stream": false
  }' | python3 -m json.tool

echo ""
echo "=== Smoke test complete ==="
