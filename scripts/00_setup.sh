#!/usr/bin/env bash
# 00_setup.sh - Create directory layout and download a GGUF model (one-time, online)
set -euo pipefail
umask 022

# Resolve project root (one directory above this script)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Cross-platform file size (GNU stat vs BSD stat)
file_size_bytes() {
  local f="$1"
  if stat -c%s "$f" >/dev/null 2>&1; then
    stat -c%s "$f"
  else
    stat -f%z "$f"
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

have_huggingface_hub() {
  have_cmd python3 && python3 -c "import huggingface_hub" >/dev/null 2>&1
}

log "=== Creating directory layout ==="
mkdir -p "$PROJECT_ROOT"/{models,workspace,logs/{inference,agent},secrets,scripts}
chmod 700 "$PROJECT_ROOT/secrets"

MODEL_DIR="$PROJECT_ROOT/models"
MANIFEST_PATH="$MODEL_DIR/model.manifest.txt"

# Configurable via environment variables
MODEL_REPO="${MODEL_REPO:-unsloth/Qwen3.5-35B-A3B-GGUF}"
MODEL_REVISION="${MODEL_REVISION:-main}"

# Keep a stable local filename even if the upstream repository renames files.
MODEL_LOCAL_NAME="${MODEL_LOCAL_NAME:-Qwen3.5-35B-A3B-Q4_K_M.gguf}"
MODEL_PATH="$MODEL_DIR/$MODEL_LOCAL_NAME"

# Candidate remote filenames (priority order)
MODEL_CANDIDATES=(
  "Qwen3.5-35B-A3B-Q4_K_M.gguf"
  "Qwen3.5-35B-A3B-UD-Q4_K_M.gguf"
)

log "=== Downloading GGUF model (one-time, requires internet) ==="
log "Repo:     $MODEL_REPO"
log "Revision: $MODEL_REVISION"
log "Local:    $MODEL_PATH"

# Try to load prior manifest (best-effort)
manifest_repo=""
manifest_rev=""
manifest_remote=""
manifest_expected_size=""
if [ -f "$MANIFEST_PATH" ]; then
  manifest_repo="$(grep -E '^repo_id=' "$MANIFEST_PATH" | head -n1 | cut -d= -f2- || true)"
  manifest_rev="$(grep -E '^revision=' "$MANIFEST_PATH" | head -n1 | cut -d= -f2- || true)"
  manifest_remote="$(grep -E '^selected_remote_file=' "$MANIFEST_PATH" | head -n1 | cut -d= -f2- || true)"
  manifest_expected_size="$(grep -E '^expected_size=' "$MANIFEST_PATH" | head -n1 | cut -d= -f2- || true)"
fi

need_download=1
if [ -f "$MODEL_PATH" ]; then
  local_size="$(file_size_bytes "$MODEL_PATH" || echo 0)"
  if [ "$local_size" -gt 0 ]; then
    # If we know the expected size from a prior run, verify completeness.
    if [ -n "$manifest_expected_size" ] && [ "$manifest_expected_size" -gt 0 ] 2>/dev/null; then
      if [ "$local_size" -eq "$manifest_expected_size" ]; then
        log "Model already exists and matches expected size (${local_size} bytes). Skipping download."
        need_download=0
      else
        log "Existing file size (${local_size} bytes) does not match expected (${manifest_expected_size} bytes). Re-downloading."
        need_download=1
      fi
    else
      # No trusted expected size -> assume it is OK if non-empty.
      # You can force re-download by deleting the file or setting FORCE_DOWNLOAD=1.
      if [ "${FORCE_DOWNLOAD:-0}" = "1" ]; then
        log "FORCE_DOWNLOAD=1 set. Re-downloading."
        need_download=1
      else
        log "Model already exists (size: ${local_size} bytes). Skipping download (no expected size available)."
        need_download=0
      fi
    fi
  fi
fi

selected_file=""
cache_path=""
commit_sha=""
expected_size=""

if [ "$need_download" -eq 1 ]; then
  mkdir -p "$MODEL_DIR"

  if have_huggingface_hub; then
    log "Using huggingface_hub (robust file selection + resumable cache download)..."

    IFS=$'\t' read -r selected_file cache_path commit_sha expected_size < <(
      MODEL_REPO="$MODEL_REPO" MODEL_REVISION="$MODEL_REVISION" \
      MODEL_CANDIDATES="$(IFS=,; echo "${MODEL_CANDIDATES[*]}")" \
      python3 - <<'PY'
import os, sys
from huggingface_hub import hf_hub_download, HfApi

repo = os.environ["MODEL_REPO"]
rev = os.environ.get("MODEL_REVISION", "main")
candidates = [x for x in os.environ.get("MODEL_CANDIDATES", "").split(",") if x]

def get_attr(obj, name):
    if isinstance(obj, dict):
        return obj.get(name)
    return getattr(obj, name, None)

api = HfApi()
try:
    files = api.list_repo_files(repo_id=repo, revision=rev)
except Exception as e:
    print(f"Failed to list repo files for {repo}@{rev}: {e}", file=sys.stderr)
    sys.exit(2)

selected = None
for cand in candidates:
    if cand in files:
        selected = cand
        break

if selected is None:
    ggufs = [f for f in files if f.endswith(".gguf")]
    print("No candidate GGUF found. Available .gguf files (first 50):", file=sys.stderr)
    for f in ggufs[:50]:
        print(f"  - {f}", file=sys.stderr)
    sys.exit(3)

try:
    cache_path = hf_hub_download(repo_id=repo, filename=selected, revision=rev)
except Exception as e:
    print(f"Download failed for {selected}: {e}", file=sys.stderr)
    sys.exit(4)

commit_sha = ""
expected_size = ""
try:
    info = api.model_info(repo_id=repo, revision=rev)
    commit_sha = get_attr(info, "sha") or ""
    sibs = get_attr(info, "siblings") or []
    size_val = None
    for s in sibs:
        if get_attr(s, "rfilename") == selected:
            size_val = get_attr(s, "size")
            break
    if size_val is not None:
        expected_size = str(int(size_val))
except Exception:
    pass

# Emit TSV for the bash caller:
# selected_file \t cache_path \t commit_sha \t expected_size
print(f"{selected}\t{cache_path}\t{commit_sha}\t{expected_size}")
PY
    )

    [ -n "${cache_path:-}" ] || die "huggingface_hub did not return a cache path."

    log "Selected remote file: $selected_file"
    [ -n "${commit_sha:-}" ] && log "Commit SHA:           $commit_sha"
    [ -n "${expected_size:-}" ] && log "Expected size:        ${expected_size} bytes"
    log "Cache path:           $cache_path"

    # Place the model into the project directory as a REAL FILE (not a symlink to HF cache),
    # so it works cleanly with Docker volume mounts.
    tmp_path="${MODEL_PATH}.tmp.$$"
    if ln -f "$cache_path" "$tmp_path" 2>/dev/null; then
      log "Hard-linked model into project directory."
    else
      log "Hardlink not possible; copying into project directory (large file, this may take time)..."
      cp -f "$cache_path" "$tmp_path"
    fi
    mv -f "$tmp_path" "$MODEL_PATH"

  else
    log "huggingface_hub not available; using wget/curl fallback..."
    downloader=""
    if have_cmd wget; then
      downloader="wget"
    elif have_cmd curl; then
      downloader="curl"
    else
      die "Neither python3+huggingface_hub nor wget/curl is available."
    fi

    success=0
    for cand in "${MODEL_CANDIDATES[@]}"; do
      url="https://huggingface.co/${MODEL_REPO}/resolve/${MODEL_REVISION}/${cand}"
      part_path="${MODEL_PATH}.download.${cand}.part"
      log "Trying: $url"
      if [ "$downloader" = "wget" ]; then
        if wget -c --show-progress -O "$part_path" "$url"; then
          mv -f "$part_path" "$MODEL_PATH"
          selected_file="$cand"
          success=1
          break
        fi
      else
        # -L follow redirects, -C - resume, --fail for HTTP errors
        if curl -L -C - --fail -o "$part_path" "$url"; then
          mv -f "$part_path" "$MODEL_PATH"
          selected_file="$cand"
          success=1
          break
        fi
      fi
      rm -f "$part_path"
    done

    [ "$success" -eq 1 ] || die "All download attempts failed (HTTP 404 or network issue)."
  fi
fi

log "=== Verifying model file ==="
[ -s "$MODEL_PATH" ] || die "Downloaded file is missing or empty: $MODEL_PATH"
ls -lh "$MODEL_PATH"

if [ -n "${expected_size:-}" ] && [ "${expected_size:-0}" -gt 0 ] 2>/dev/null; then
  final_size="$(file_size_bytes "$MODEL_PATH" || echo 0)"
  if [ "$final_size" -ne "$expected_size" ]; then
    die "Size mismatch after download: got ${final_size} bytes, expected ${expected_size} bytes."
  fi
fi

# Optional checksum (slow for ~20GB). Enable with VERIFY_SHA256=1
if [ "${VERIFY_SHA256:-0}" = "1" ]; then
  if have_cmd sha256sum; then
    log "=== SHA256 (requested) ==="
    sha256sum "$MODEL_PATH"
  elif have_cmd shasum; then
    log "=== SHA256 (requested) ==="
    shasum -a 256 "$MODEL_PATH"
  else
    log "SHA256 requested but no sha256 tool found; skipping."
  fi
fi

# Write a small manifest for reproducibility
{
  echo "repo_id=$MODEL_REPO"
  echo "revision=$MODEL_REVISION"
  echo "local_file=$MODEL_LOCAL_NAME"
  [ -n "${selected_file:-}" ] && echo "selected_remote_file=$selected_file"
  [ -n "${commit_sha:-}" ] && echo "commit_sha=$commit_sha"
  [ -n "${expected_size:-}" ] && echo "expected_size=$expected_size"
  echo "downloaded_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$MANIFEST_PATH"
log "Wrote manifest: $MANIFEST_PATH"

log ""
log "Setup complete. Internet can now be disconnected."
log "Run: cd $PROJECT_ROOT && docker compose up -d"
