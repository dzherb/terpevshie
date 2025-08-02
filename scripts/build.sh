#!/usr/bin/env bash
set -euo pipefail

THREADS="${1:-4}"

HASH_FILE=".jinja2_hashes"
TEMP_HASH_FILE=".jinja2_hashes.tmp"
JINJA_LIST_FILE=".jinja2_files.tmp"
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
find pages -path pages/common -prune -o -type f -name "*.jinja2" ! -name "*.html" -print > "$JINJA_LIST_FILE"

process_file() {
  local file="$1"
  local dir base out hash
  dir=$(dirname "$file")
  base=$(basename "$file" .jinja2)
  out="$dir/$base.html"

  echo "$out" >> "$GENERATED_FILE_LIST"

  hash=$(shasum -a 256 "$file" | awk '{print $1}')
  if grep -qF "$file $hash" "$HASH_FILE" 2>/dev/null; then
    echo "⏭  Skipping unchanged: $file"
    echo "$file $hash" >> "$TEMP_HASH_FILE"
    return
  fi

  echo "⚙️  Rendering: $file → $out"
  minijinja-cli "$file" > "$out"

  echo "⚙️  Minifying: $out"
  npx --yes html-minifier-terser "$out" \
    --collapse-whitespace \
    --remove-comments \
    --minify-css true \
    --minify-js true \
    -o "$out" 2>/dev/null

  echo "$file $hash" >> "$TEMP_HASH_FILE"
  echo "✅  Done: $out"
}

export -f process_file
export HASH_FILE TEMP_HASH_FILE GENERATED_FILE_LIST

cat "$JINJA_LIST_FILE" | xargs -P "$THREADS" -n 1 bash -c 'process_file "$0"'

sort "$TEMP_HASH_FILE" > "$HASH_FILE"

echo "🧹 Checking for outdated .html files..."
find pages -type f -name "*.html" | while read -r file; do
  if ! grep -Fxq "$file" "$GENERATED_FILE_LIST"; then
    echo "❌  Deleting outdated: $file"
    rm -f "$file"
  fi
done

echo "🏁 All done!"
