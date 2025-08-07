#!/usr/bin/env bash
set -euo pipefail

THREADS="${1:-4}"

WORK_DIR="pages"
EXCLUDE_DIR="common"

cd "$WORK_DIR"

HASH_FILE=".build_hashes"
TEMP_HASH_FILE=".build_hashes.tmp"
JINJA_LIST_FILE=".build_files.tmp"
GENERATED_FILE_LIST=".generated_html.tmp"
TEMP_FILES=("$TEMP_HASH_FILE" "$JINJA_LIST_FILE" "$GENERATED_FILE_LIST")

cleanup() {
  echo "🧹 Cleaning up temporary files..."
  for f in "${TEMP_FILES[@]}"; do
    [ -f "$f" ] && rm -f "$f"
  done
}
trap cleanup EXIT INT TERM

> "$TEMP_HASH_FILE"
> "$GENERATED_FILE_LIST"

echo "🔍 Searching for .jinja2 files..."
find . -path "./$EXCLUDE_DIR" -prune -o -type f -name "*.jinja2" ! -name "*.html" -print > "$JINJA_LIST_FILE"

# Parse dependencies: {% include '...' %} or {% extends "..." %}
get_dependencies() {
  local file="$1"
  grep -oE "{% *(include|extends) *['\"]([^'\"]+)['\"] *%}" "$file" \
    | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" \
    | sort -u
}

# Compute combined hash of a template file + all its dependencies recursively
compute_full_hash() {
  local file="$1"
  local combined=""
  local seen=""

  _hash_recursive() {
    local current_file="$1"
    local current_dir
    current_dir=$(dirname "$current_file")

    # Avoid circular dependencies
    if echo "$seen" | grep -Fxq "$current_file"; then
      return
    fi
    seen="$seen"$'\n'"$current_file"

    if [[ ! -f "$current_file" ]]; then
      return
    fi

    # Add file hash
    local file_hash
    file_hash=$(shasum -a 256 "$current_file" | awk '{print $1}')
    combined+="$file_hash"

    # Parse dependencies relative to the current file
    local dep
    while read -r dep; do
      [[ -z "$dep" ]] && continue
      local dep_path="$current_dir/$dep"
      _hash_recursive "$dep_path"
    done < <(get_dependencies "$current_file")
  }

  _hash_recursive "$file"

  echo -n "$file "
  echo -n "$combined" | shasum -a 256 | awk '{print $1}'
}

process_file() {
  local file="$1"
  local dir base out full_hash
  dir=$(dirname "$file")
  base=$(basename "$file" .jinja2)
  out="$dir/$base.html"

  echo "$out" >> "$GENERATED_FILE_LIST"

  full_hash=$(compute_full_hash "$file")

  if grep -qF "$full_hash" "$HASH_FILE" 2>/dev/null; then
    echo "⏭  Skipping unchanged: $file"
    echo "$full_hash" >> "$TEMP_HASH_FILE"
    return
  fi

  echo "⚙️  Rendering: $file → $out"
  if ! minijinja-cli "$file" > "$out"; then
    echo "❌  Failed to render $file"
    return 1
  fi

  echo "⚙️  Minifying: $out"
  npx --yes html-minifier-terser "$out" \
    --collapse-whitespace \
    --remove-comments \
    --minify-css true \
    --minify-js true \
    -o "$out" 2>/dev/null

  echo "$full_hash" >> "$TEMP_HASH_FILE"
  echo "✅  Done: $out"
}

export -f get_dependencies
export -f compute_full_hash
export -f process_file
export HASH_FILE TEMP_HASH_FILE GENERATED_FILE_LIST

cat "$JINJA_LIST_FILE" | xargs -P "$THREADS" -n 1 bash -c 'process_file "$0"'

sort "$TEMP_HASH_FILE" > "$HASH_FILE"

echo "🏁 All done!"
