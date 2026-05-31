#!/bin/bash
# ==============================================================================
# Blog auto-publish (runs on the acquisition VM via /etc/cron.d/blog-pull)
# ==============================================================================
# Pulls the blog repo and rebuilds the container only when origin/main changed,
# so Keystatic commits (including phone edits) go live within a few minutes
# without a terraform apply. Runs as the ubuntu user (passwordless docker sudo).
set -uo pipefail

REPO_DIR=/opt/acquisition/blog
LOG=/var/log/blog-pull.log

cd "${REPO_DIR}" || exit 0

git fetch --quiet origin main 2>>"${LOG}" || exit 0
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)
if [ "${LOCAL}" = "${REMOTE}" ]; then
  exit 0
fi

{
  echo "$(date -Is) blog change ${LOCAL} -> ${REMOTE}, rebuilding"
  git pull --quiet --ff-only origin main
  sudo docker compose up -d --build
  echo "$(date -Is) blog rebuild done"
} >>"${LOG}" 2>&1
