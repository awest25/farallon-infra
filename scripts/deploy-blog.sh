#!/bin/bash
# ==============================================================================
# Blog deploy (rendered by Terraform templatefile, run on the acquisition VM)
# ==============================================================================
# Clones/updates the standalone blog repo, writes blog.env (Keystatic GitHub
# mode secrets), builds the container on :3001, and installs the auto-publish
# cron. Safe to re-run.
#
# NOTE: $${...} tokens are Terraform templatefile values; bash variables use the
# unbraced $VAR form so templatefile does not try to interpolate them.
set -uo pipefail

REPO_DIR=/opt/acquisition/blog
REPO_URL="${blog_repo_url}"

# --- ensure git is present ----------------------------------------------------
command -v git >/dev/null 2>&1 || { sudo apt-get update -qq && sudo apt-get install -y -qq git; }

# --- clone or update ----------------------------------------------------------
sudo mkdir -p "$REPO_DIR"
sudo chown -R ubuntu:ubuntu "$REPO_DIR"
if [ -d "$REPO_DIR/.git" ]; then
  cd "$REPO_DIR"
  git fetch --quiet origin main
  git reset --hard origin/main
else
  git clone --quiet "$REPO_URL" "$REPO_DIR"
  cd "$REPO_DIR"
fi

# --- blog.env (Keystatic GitHub mode) ----------------------------------------
# Ignored by the repo's .gitignore, so reset/pull never clobbers it.
tee "$REPO_DIR/blog.env" >/dev/null <<EOF
NODE_ENV=production
KEYSTATIC_GITHUB_REPO=${keystatic_github_repo}
KEYSTATIC_GITHUB_CLIENT_ID=${keystatic_github_client_id}
KEYSTATIC_GITHUB_CLIENT_SECRET=${keystatic_github_client_secret}
KEYSTATIC_SECRET=${keystatic_secret}
PUBLIC_KEYSTATIC_GITHUB_APP_SLUG=${keystatic_github_app_slug}
EOF
chmod 600 "$REPO_DIR/blog.env"

# --- build-time public var (docker compose auto-reads .env for variable subs) ---
# PUBLIC_ Astro vars are inlined at build, so the slug must be a build arg, not
# just runtime env. Not secret. Persists across the cron's rebuilds.
printf 'PUBLIC_KEYSTATIC_GITHUB_APP_SLUG=%s\n' "${keystatic_github_app_slug}" > "$REPO_DIR/.env"

# --- build + start ------------------------------------------------------------
cd "$REPO_DIR" && sudo docker compose up -d --build

# --- install auto-publish cron -----------------------------------------------
sudo touch /var/log/blog-pull.log && sudo chown ubuntu:ubuntu /var/log/blog-pull.log
sudo install -m 0755 /tmp/blog-pull-and-build.sh /usr/local/bin/blog-pull-and-build.sh
echo '*/5 * * * * ubuntu /usr/local/bin/blog-pull-and-build.sh' | sudo tee /etc/cron.d/blog-pull >/dev/null
sudo chmod 0644 /etc/cron.d/blog-pull
echo "blog deploy complete"
