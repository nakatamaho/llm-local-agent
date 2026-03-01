#!/usr/bin/env bash
# scripts/01_build_and_launch.sh
# Build Docker images and start the stack (OFFLINE - no internet needed after model download)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

if [ ! -f ".env" ]; then
    echo "ERROR: .env not found. Copy .env.example to .env and set PROJECT_ROOT."
    exit 1
fi

source .env

if [ ! -f "models/${MODEL_FILE:-Qwen3.5-35B-A3B-Q4_K_M.gguf}" ]; then
    echo "ERROR: Model file not found at models/${MODEL_FILE:-Qwen3.5-35B-A3B-Q4_K_M.gguf}"
    echo "Run scripts/00_setup.sh first (requires internet, one-time only)."
    exit 1
fi

echo "=== Building inference image (llama.cpp + CUDA) ==="
# NOTE: This build requires internet to git clone llama.cpp.
# For fully offline builds, pre-build and save the image first:
#   docker save llm-local-agent/inference:b5576 | gzip > inference_image.tar.gz
#   docker load < inference_image.tar.gz
docker compose build --no-cache inference

echo "=== Building agent image (aider) ==="
# Same note: aider pip install requires internet.
# Pre-save: docker save llm-local-agent/agent:0.85.2 | gzip > agent_image.tar.gz
docker compose build --no-cache agent

echo "=== Starting inference server ==="
docker compose up -d inference

echo "=== Waiting for inference server to be healthy ==="
max_wait=300  # 5 minutes max for model load
elapsed=0
until docker compose exec inference curl -sf http://localhost:8080/health &>/dev/null; do
    if [ $elapsed -ge $max_wait ]; then
        echo "ERROR: Inference server failed to start within ${max_wait}s"
        docker compose logs inference | tail -30
        exit 1
    fi
    echo "  Waiting... (${elapsed}s / ${max_wait}s)"
    sleep 10
    elapsed=$((elapsed + 10))
done
echo "Inference server is healthy!"

echo ""
echo "=== Stack is ready ==="
echo "Start aider agent:"
echo "  docker compose run --rm agent aider --model openai/Qwen3.5-35B-A3B [files...]"
echo ""
echo "Or drop into agent shell:"
echo "  docker compose run --rm agent bash"
echo ""
echo "Check inference logs:"
echo "  docker compose logs -f inference"
