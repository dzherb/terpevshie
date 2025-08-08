#!/usr/bin/env bash
set -euo pipefail

# Load .env without overwriting existing env variables
if [ -f .env ]; then
  IFS=$'\n'
  for l in $(cat .env); do
      IFS='=' read -ra VARVAL <<< "$l"
      eval "export ${VARVAL[0]}=\${${VARVAL[0]}:-${VARVAL[1]}}"
  done
  unset IFS
fi

: "${SSH_TARGET:?Need to set SSH_TARGET (alias or user@host)}"
SSH_OPTIONS="${SSH_OPTIONS:-}"
: "${REMOTE_DIR:?Need to set REMOTE_DIR}"

LOCAL_DIR="${1:-}"

if [ -z "$LOCAL_DIR" ]; then
  echo "Usage: $0 /path/to/local/static"
  exit 1
fi

if [ ! -d "$LOCAL_DIR" ]; then
  echo "Local directory '$LOCAL_DIR' does not exist or is not a directory"
  exit 1
fi

echo "Deploying $LOCAL_DIR to $SSH_TARGET:$REMOTE_DIR"

rsync -avz --delete -e "ssh $SSH_OPTIONS" "$LOCAL_DIR"/ "$SSH_TARGET:$REMOTE_DIR/"

echo "✅ Deployment completed."
