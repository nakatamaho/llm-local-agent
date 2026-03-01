#!/usr/bin/env bash
# docs/usage_examples.sh
# This file is DOCUMENTATION only - copy-paste commands from here

# ============================================================
# A. Start the stack (after initial setup)
# ============================================================
cd /path/to/llm-local-agent

# Start inference server (stays running)
docker compose up -d inference

# Wait for healthy state
docker compose exec inference curl -sf http://localhost:8080/health

# ============================================================
# B. Launch aider for interactive coding session
# ============================================================

# Option 1: aider with specific files
docker compose run --rm -it agent \
  aider \
  --model openai/Qwen3.5-35B-A3B \
  --openai-api-base http://172.30.0.10:8080/v1 \
  --openai-api-key dummy \
  src/Rlapack.cpp include/mplapack/mplapack.h

# Option 2: aider on whole repo (uses repo-map automatically)
docker compose run --rm -it agent \
  aider \
  --model openai/Qwen3.5-35B-A3B \
  --openai-api-base http://172.30.0.10:8080/v1 \
  --openai-api-key dummy \
  --map-tokens 8192 \
  .  # pass repo root - aider builds ctags map

# Inside aider session, example commands:
# /add src/Rlapack.cpp          <- add file to context
# /ask What does Rlapack_ilaenv do?   <- ask without editing
# /drop src/bigfile.cpp         <- remove from context
# /map                          <- show current repo map
# /tokens                       <- show token usage
# /test make test               <- run tests in container
# /quit

# ============================================================
# C. Patch generation → apply → test (non-interactive)
# ============================================================

# Generate a patch for a bug fix
docker compose run --rm agent \
  aider \
  --model openai/Qwen3.5-35B-A3B \
  --openai-api-base http://172.30.0.10:8080/v1 \
  --openai-api-key dummy \
  --message "Fix the off-by-one error in the bisection loop in Rlasq2.cpp. \
             The iteration count should not exceed maxit." \
  --yes \
  --no-auto-commits \
  src/Rlasq2.cpp

# After aider applies the patch (in /workspace), verify:
docker compose run --rm agent \
  git -C /workspace diff HEAD

# Apply the patch manually if aider did dry-run:
# docker compose run --rm agent patch -p1 -i /workspace/fix.patch

# ============================================================
# D. Run tests inside sandbox (network-isolated)
# ============================================================

# Simple: exec build/test inside agent container
docker compose run --rm agent bash -c "
  cd /workspace && \
  mkdir -p build && \
  cd build && \
  cmake .. -DCMAKE_BUILD_TYPE=Debug && \
  make -j$(nproc) && \
  ctest --output-on-failure
"

# Strict isolation: launch one-off container with --network none
# (docker compose doesn't support network:none; use docker run)
docker run --rm \
  --network none \
  --security-opt no-new-privileges:true \
  --cap-drop ALL \
  --memory 8g \
  --cpus 4 \
  -v /path/to/your/repo:/workspace:rw \
  ubuntu:24.04 \
  bash -c "cd /workspace && make test"

# ============================================================
# E. Large repo: index first, then use
# ============================================================

# Step 1: Index the repo (run once, or after major changes)
docker compose run --rm agent \
  bash /workspace/.llm-index/index_repo.sh /workspace

# Step 2: Start aider with index as context
docker compose run --rm -it agent \
  aider \
  --model openai/Qwen3.5-35B-A3B \
  --openai-api-base http://172.30.0.10:8080/v1 \
  --openai-api-key dummy \
  /workspace/.llm-index/repo_stats.txt \
  /workspace/.llm-index/definitions.txt

# Inside aider: /ask <question about the codebase>

# ============================================================
# F. Offline image persistence (for airgapped environments)
# ============================================================

# Save images AFTER building (on internet-connected machine):
docker save llm-local-agent/inference:b5576 | gzip > inference_b5576.tar.gz
docker save llm-local-agent/agent:0.85.2   | gzip > agent_0.85.2.tar.gz

# Load on airgapped machine:
docker load < inference_b5576.tar.gz
docker load < agent_0.85.2.tar.gz

# Transfer model file separately (scp, rsync, USB, etc.):
rsync -avP models/Qwen3.5-35B-A3B-Q4_K_M.gguf user@airgapped-host:/path/to/models/
