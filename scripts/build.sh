#!/usr/bin/env bash
set -euo pipefail

THREADS="${1:-4}"

SOURCE_DIR="pages"
SOURCE_EXCLUDE_DIR="common/jinja"
DATA_FILE="$SOURCE_EXCLUDE_DIR/data.yaml"
BUILD_DIR="dist"

rsync -a --delete $SOURCE_DIR/ $BUILD_DIR/

cd "$BUILD_DIR"

process_file() {
  local file="$1"
  local dir base out page_path
  dir=$(dirname "$file")
  base=$(basename "$file" .jinja2)
  out="$dir/$base.html"

  # Канонический URL страницы: ./concerts/index.jinja2 → /concerts, ./404.jinja2 → /404.html
  page_path="${dir#.}"
  if [ "$base" != "index" ]; then
    page_path="$page_path/$base.html"
  fi
  page_path="${page_path:-/}"

  echo "⚙️  Rendering: $file → $out"
  if ! minijinja-cli "$file" "$DATA_FILE" -D page_path="$page_path" > "$out"; then
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

  rm $file
  echo "✅  Done: $out"
}

export -f process_file
export DATA_FILE

echo "🔍 Searching for .jinja2 files..."
find . -path "./$SOURCE_EXCLUDE_DIR" -prune -o -type f -name "*.jinja2" -print \
  | xargs -P "$THREADS" -n 1 bash -c 'process_file "$0"'

rm -r $SOURCE_EXCLUDE_DIR
find . -name ".DS_Store" -delete

echo "🏁 All done!"
