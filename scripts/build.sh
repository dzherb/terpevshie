#!/usr/bin/env bash
set -euo pipefail

THREADS="${1:-4}"

SOURCE_DIR="pages"
SOURCE_EXCLUDE_DIR="common/jinja"
DATA_FILE="$SOURCE_EXCLUDE_DIR/data.yaml"
BUILD_DIR="dist"

MINIFIER="html-minifier-terser@7.2.0"

rsync -a --delete $SOURCE_DIR/ $BUILD_DIR/

cd "$BUILD_DIR"

render_file() {
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

  rm "$file"
}

export -f render_file
export DATA_FILE

echo "🔍 Searching for .jinja2 files..."
find . -path "./$SOURCE_EXCLUDE_DIR" -prune -o -type f -name "*.jinja2" -print \
  | xargs -P "$THREADS" -n 1 bash -c 'render_file "$0"'

echo "🗺  Generating sitemap.xml..."
# Пути собранных страниц: ./concerts/index.html → /concerts, ./index.html → /
# 404 и черновики из experimental/ в индекс не отдаём.
pages=$(find . -type f -name "*.html" -not -name "404.html" \
  -not -path "./experimental/*" -not -path "./$SOURCE_EXCLUDE_DIR/*" \
  | sed -e 's|^\.||' -e 's|/index\.html$||' -e 's|^$|/|' \
  | sort)
pages_json=$(printf '%s\n' "$pages" | awk 'NF {printf "%s\"%s\"", sep, $0; sep=","}')

minijinja-cli "$SOURCE_EXCLUDE_DIR/sitemap.xml.jinja2" "$DATA_FILE" \
  -D "pages:=[$pages_json]" -o sitemap.xml

rm -r $SOURCE_EXCLUDE_DIR

echo "🗜  Minifying..."
npx --yes "$MINIFIER" \
  --input-dir . \
  --output-dir . \
  --file-ext html \
  --collapse-whitespace \
  --remove-comments \
  --minify-css true \
  --minify-js true

find . -name ".DS_Store" -delete

echo "🏁 All done!"
