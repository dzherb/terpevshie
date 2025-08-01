#!/usr/bin/env bash

set -euo pipefail

echo "🔍 Searching for .html files..."

find . -type f -name "*.html" ! -name "*.min.html" | while read -r file; do
  dir=$(dirname "$file")
  base=$(basename "$file" .html)
  out="$dir/$base.min.html"

  echo "⚙️  Minifying: $file → $out"

  npx --yes html-minifier-terser "$file" \
    --collapse-whitespace \
    --remove-comments \
    --remove-optional-tags \
    --minify-css true \
    --minify-js true \
    -o "$out" 2> /dev/null

  echo "✅  Done: $out"
done

echo "🏁 All HTML files have been minified."
