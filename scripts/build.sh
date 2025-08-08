#!/usr/bin/env bash
set -euo pipefail

THREADS="${1:-4}"

SOURCE_DIR="pages"
SOURCE_EXCLUDE_DIR="common/jinja"
BUILD_DIR="dist"

[ -d "$BUILD_DIR" ] && rm -r $BUILD_DIR
cp -R $SOURCE_DIR $BUILD_DIR

cd "$BUILD_DIR"

process_file() {
  local file="$1"
  local dir base out
  dir=$(dirname "$file")
  base=$(basename "$file" .jinja2)
  out="$dir/$base.html"

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

  rm $file
  echo "✅  Done: $out"
}

export -f process_file

echo "🔍 Searching for .jinja2 files..."
find . -path "./$SOURCE_EXCLUDE_DIR" -prune -o -type f -name "*.jinja2" -print \
  | xargs -P "$THREADS" -n 1 bash -c 'process_file "$0"'

rm -r $SOURCE_EXCLUDE_DIR

echo "🏁 All done!"
