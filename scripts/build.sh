#!/usr/bin/env bash

set -euo pipefail

echo "🔍 Searching for .jinja files..."

find pages -type f -name "*.jinja2" ! -name "*.html" | while read -r file; do
  dir=$(dirname "$file")
  base=$(basename "$file" .jinja2)
  out="$dir/$base.html"

  echo "⚙️  Rendering: $file → $out"

  minijinja-cli $file > $out

  echo "⚙️  Minifying: $out"

  npx --yes html-minifier-terser "$out" \
    --collapse-whitespace \
    --remove-comments \
    --minify-css true \
    --minify-js true \
    -o "$out" 2> /dev/null

  echo "✅  Done: $out"
done

echo "🏁 All HTML files have been built."
