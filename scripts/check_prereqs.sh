#!/usr/bin/env bash
# check_prereqs.sh - Verify host prerequisites before setup
set -euo pipefail

ERRORS=0

check() {
    local name="$1"
    local cmd="$2"
    if eval "$cmd" &>/dev/null; then
        echo "[OK]  $name"
    else
        echo "[FAIL] $name"
        ERRORS=$((ERRORS + 1))
    fi
}

echo "=== Host Prerequisites Check ==="
check "Docker >= 24"          "docker version --format '{{.Server.Version}}' | awk -F. '\$1>=24'"
check "docker compose v2"     "docker compose version"
check "nvidia-smi"            "nvidia-smi"
check "nvidia-container-toolkit" "docker run --rm --gpus all --network none nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L"
check "CUDA >= 12.1"          "nvidia-smi | grep -oP 'CUDA Version: \K[0-9]+\.[0-9]+' | awk -F. '\$1>12||(\$1==12&&\$2>=1)'"
check "Free disk >= 50GB"     "df -BG . | awk 'NR==2{gsub(/G/,\"\",\$4); exit (\$4>=50 ? 0 : 1)}'"
check "RAM >= 32GB"           "free -g | awk '/^Mem/{exit (\$2>=32 ? 0 : 1)}'"
check "curl"                  "which curl"
check "huggingface_hub or wget" "python3 -c 'import huggingface_hub' || which wget"

echo ""
if [ "$ERRORS" -gt 0 ]; then
    echo "FAILED: $ERRORS check(s) failed. Fix before proceeding."
    exit 1
else
    echo "All checks passed."
fi
