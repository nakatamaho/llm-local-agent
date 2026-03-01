#!/usr/bin/env bash
# QUICKSTART.sh
# Copy-paste from top to bottom. Requires internet for steps 1-3 only.
# After step 3, disconnect internet and everything runs offline.

set -euo pipefail

# ── STEP 1: Clone this repo structure ────────────────────────────────────────
mkdir -p ~/llm-local-agent
cd ~/llm-local-agent

# Copy all files from this project, then:
cp .env.example .env
# EDIT .env: set PROJECT_ROOT and WORKSPACE_PATH
nano .env   # or vim .env

# ── STEP 2: Download model (one-time, ~20GB) ─────────────────────────────────
pip install huggingface_hub   # or: sudo apt install python3-pip && pip3 install huggingface_hub
bash scripts/00_setup.sh

# ── STEP 3: Build Docker images (requires internet for apt/pip/git) ──────────
docker compose build inference
docker compose build agent

# === DISCONNECT INTERNET HERE ================================================
# sudo iptables -I FORWARD -j DROP   # optional: block forwarding at host level

# ── STEP 4: Launch inference server ──────────────────────────────────────────
docker compose up -d inference

# Wait for model to load (~60-90 seconds)
echo "Waiting for model to load..."
until docker compose exec inference curl -sf http://localhost:8080/health; do
    sleep 5; printf '.'
done
echo " Ready!"

# ── STEP 5: Start coding agent ───────────────────────────────────────────────
# Replace /path/to/your/repo with your actual workspace
export WORKSPACE_PATH=/path/to/your/repo

# Quick interactive session:
docker compose run --rm -it agent \
  aider \
  --model openai/Qwen3.5-35B-A3B \
  --openai-api-base http://172.30.0.10:8080/v1 \
  --openai-api-key dummy \
  --map-tokens 4096

# ── EXAMPLE: Ask something about the repo ────────────────────────────────────
# Inside aider:
# > /ask What is the overall structure of this project?
# > /add src/main.cpp
# > Fix the memory leak in the parse_input function
# > /test make test

# ── SHUTDOWN ─────────────────────────────────────────────────────────────────
# docker compose down
