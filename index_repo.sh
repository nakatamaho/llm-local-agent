#!/usr/bin/env bash
# scripts/index_repo.sh
# Build symbol index and compressed summary for large repositories.
# Run this INSIDE the agent container: docker exec -it llm-agent bash index_repo.sh
# Or mount and run: docker exec llm-agent /workspace/.llm-index/index_repo.sh
set -euo pipefail

REPO_DIR="${1:-/workspace}"
INDEX_DIR="$REPO_DIR/.llm-index"
MAX_FILE_SIZE_KB=500   # Skip files larger than this (binary/generated)

mkdir -p "$INDEX_DIR"

echo "=== Indexing: $REPO_DIR ==="
cd "$REPO_DIR"

# 1. File tree (excluding build artifacts)
echo "[1/5] Generating file tree..."
find . \
    -not -path './.git/*' \
    -not -path './.llm-index/*' \
    -not -path './node_modules/*' \
    -not -path './build/*' \
    -not -path './_build/*' \
    -not -path './dist/*' \
    -not -name '*.o' \
    -not -name '*.a' \
    -not -name '*.so' \
    -not -name '*.pyc' \
    -type f \
    | sort > "$INDEX_DIR/file_list.txt"

echo "  Found $(wc -l < "$INDEX_DIR/file_list.txt") files."

# 2. ctags symbol index
echo "[2/5] Building ctags index..."
if command -v ctags &>/dev/null; then
    ctags \
        --recurse \
        --exclude=.git \
        --exclude=node_modules \
        --exclude=build \
        --exclude="*.o" \
        --exclude="*.a" \
        --output-format=json \
        --fields='*' \
        -f "$INDEX_DIR/tags.json" \
        . 2>/dev/null || true
    echo "  ctags: $(wc -l < "$INDEX_DIR/tags.json") symbols"
else
    echo "  [WARN] ctags not found, skipping."
fi

# 3. ripgrep function/class summary per file
echo "[3/5] Extracting top-level definitions with ripgrep..."
if command -v rg &>/dev/null; then
    rg \
        --no-heading \
        --line-number \
        -e '^\s*(def |class |fn |func |function |pub fn |pub struct |impl |#define )' \
        --glob '!.git' \
        --glob '!*.o' \
        . > "$INDEX_DIR/definitions.txt" 2>/dev/null || true
    echo "  $(wc -l < "$INDEX_DIR/definitions.txt") definitions found."
else
    echo "  [WARN] ripgrep not found, skipping."
fi

# 4. Compressed per-file summaries (first 50 lines of each source file)
echo "[4/5] Building quick-view summaries..."
SUMMARY_DIR="$INDEX_DIR/summaries"
mkdir -p "$SUMMARY_DIR"

while IFS= read -r filepath; do
    # Skip large files and binaries
    size_kb=$(du -k "$filepath" 2>/dev/null | cut -f1 || echo "9999")
    if [ "$size_kb" -gt "$MAX_FILE_SIZE_KB" ]; then
        continue
    fi
    # Skip non-text files (rough check)
    if ! file "$filepath" | grep -qiE 'text|script|source'; then
        continue
    fi
    safe_name=$(echo "${filepath#./}" | tr '/' '__')
    head -50 "$filepath" > "$SUMMARY_DIR/${safe_name}.head" 2>/dev/null || true
done < "$INDEX_DIR/file_list.txt"

echo "  $(ls "$SUMMARY_DIR" | wc -l) file summaries created."

# 5. Stats
echo "[5/5] Repository stats..."
{
    echo "Repository: $REPO_DIR"
    echo "Indexed at: $(date -u)"
    echo "Total files: $(wc -l < "$INDEX_DIR/file_list.txt")"
    echo ""
    echo "=== File type breakdown ==="
    awk -F. '{print $NF}' "$INDEX_DIR/file_list.txt" | sort | uniq -c | sort -rn | head -20
    echo ""
    echo "=== Directory structure (depth 3) ==="
    find . -maxdepth 3 -type d \
        -not -path './.git*' \
        -not -path './.llm-index*' \
        -not -path './node_modules*' \
        | sort
} > "$INDEX_DIR/repo_stats.txt"

cat "$INDEX_DIR/repo_stats.txt"

echo ""
echo "=== Index complete: $INDEX_DIR ==="
echo "To include in aider context, run inside aider:"
echo "  /add .llm-index/repo_stats.txt"
echo "  /add .llm-index/definitions.txt"
