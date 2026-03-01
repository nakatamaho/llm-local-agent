#!/usr/bin/env bash
# 00_setup.sh - Create directory layout and download model (one-time, online)
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Creating directory layout ==="
mkdir -p "$PROJECT_ROOT"/{models,workspace,logs/{inference,agent},secrets,scripts}

# Set permissions: secrets dir only accessible by owner
chmod 700 "$PROJECT_ROOT/secrets"

echo "=== Downloading GGUF model (one-time, requires internet) ==="
# Model: Qwen3.5-35B-A3B-Q4_K_M.gguf (~20GB)
# Adjust filename if the repo uses a different shard naming
MODEL_REPO="unsloth/Qwen3.5-35B-A3B-GGUF"
MODEL_FILE="Qwen3.5-35B-A3B-Q4_K_M.gguf"
MODEL_DIR="$PROJECT_ROOT/models"

if [ -f "$MODEL_DIR/$MODEL_FILE" ]; then
    echo "Model already exists at $MODEL_DIR/$MODEL_FILE, skipping download."
else
    # Option A: huggingface_hub (recommended - handles resumable downloads)
    if python3 -c "import huggingface_hub" 2>/dev/null; then
        echo "Using huggingface_hub..."
        python3 -c "
from huggingface_hub import hf_hub_download
import os
path = hf_hub_download(
    repo_id='$MODEL_REPO',
    filename='$MODEL_FILE',
    local_dir='$MODEL_DIR',
    resume_download=True,
)
print(f'Downloaded to: {path}')
"
    # Option B: wget fallback
    else
        echo "Using wget (no resume on partial if server doesn't support it)..."
        wget -c \
            "https://huggingface.co/$MODEL_REPO/resolve/main/$MODEL_FILE" \
            -O "$MODEL_DIR/$MODEL_FILE"
    fi
fi

echo "=== Verifying model file ==="
ls -lh "$MODEL_DIR/$MODEL_FILE"
echo ""
echo "Setup complete. Internet can now be disconnected."
echo "Run: cd $PROJECT_ROOT && docker compose up -d"
