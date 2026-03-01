#!/usr/bin/env bash
# docs/troubleshoot.sh - Diagnosis commands for common issues

# ============================================================
# ISSUE 1: nvidia-container-toolkit / GPU not visible
# ============================================================

# Symptom: "could not select device driver" or CUDA error in container

# Fix: Install nvidia-container-toolkit on HOST
# Ubuntu 24.04:
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Verify:
docker run --rm --gpus all --network none \
  nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi

# ============================================================
# ISSUE 2: VRAM insufficient / OOM
# ============================================================

# Check current GPU usage:
nvidia-smi --query-gpu=memory.used,memory.free,memory.total --format=csv

# Diagnosis: Q4_K_M model should use ~20GB. If OOM:
# - Reduce context: set LLAMA_CTX_SIZE=32768 in .env
# - Reduce batch: LLAMA_BATCH_SIZE=256
# - Use smaller quant: Q2_K (~11GB, quality loss) as fallback

# Monitor VRAM during model load:
watch -n1 nvidia-smi

# ============================================================
# ISSUE 3: Slow inference (low tokens/sec)
# ============================================================

# Expected: Qwen3.5-35B-A3B (MoE, 3B active) on A100 80GB
# Q4_K_M: ~40-80 tok/s for generation (only 3B params active, fast!)
# If much slower:

# Check if GPU offload is active (-ngl 99 was passed):
docker compose logs inference | grep "offloaded"
# Should show: "offloaded X/40 layers to GPU"

# Check if using PCIe vs NVLink (doesn't apply for single GPU)
# Check CPU threads aren't bottlenecking:
docker compose exec inference cat /proc/cpuinfo | grep "model name" | head -1

# ============================================================
# ISSUE 4: aider can't connect to inference server
# ============================================================

# From agent container, test connectivity:
docker compose exec agent curl -sf http://172.30.0.10:8080/health

# If fails: check inference is on correct network
docker network ls
docker inspect llm-local-agent_llm-internal | python3 -m json.tool

# Verify inference IP:
docker inspect llm-inference | grep -A5 '"llm-internal"'

# ============================================================
# ISSUE 5: Generation quality / wrong output
# ============================================================

# For coding tasks:
# - Temperature: 0.2-0.4 (more deterministic)
# - top_p: 0.9-0.95
# - min_p: 0.05 (cuts low-probability tokens, helps quality)
# - repeat_penalty: 1.05-1.1 (prevents loops)

# Qwen3.5 has "thinking mode" (/think tag) - add to system prompt:
# "Think carefully step by step before answering."
# Or use the <think> tags in messages if needed.

# If aider produces bad diffs (doesn't apply cleanly):
# Switch edit-format in aider.conf.yml: whole (instead of diff)
# This sends complete file content, slower but more reliable.

# ============================================================
# ISSUE 6: llama-server build fails (Dockerfile.inference)
# ============================================================

# Symptom: cmake or make error
# - Verify CUDA toolkit version matches base image (12.4)
# - Pin LLAMA_CPP_VERSION to a known-good tag
# - Check: https://github.com/ggerganov/llama.cpp/releases

# Alternative: Use pre-built image from GHCR (if available, may not have exact version):
# FROM ghcr.io/ggerganov/llama.cpp:server-cuda AS runtime
# But this loses version pinning. Use only for quick testing.

# ============================================================
# ISSUE 7: aider pip install fails at build (offline image build)
# ============================================================

# Pre-download pip packages on internet machine:
pip download aider-chat==0.85.2 -d ./pip-cache/
# Then in Dockerfile.agent:
# COPY pip-cache/ /pip-cache/
# RUN pip install --no-index --find-links=/pip-cache aider-chat==0.85.2
