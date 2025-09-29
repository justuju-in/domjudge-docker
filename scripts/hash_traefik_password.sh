#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env.dev}"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Environment file $ENV_FILE not found!"
  exit 1
fi

echo "🔑 Generating TRAEFIK_HASHED_PASSWORD from TRAEFIK_PLAINTEXT_PASSWORD in $ENV_FILE..."

PLAINTEXT=$(grep '^TRAEFIK_PLAINTEXT_PASSWORD=' "$ENV_FILE" | cut -d'=' -f2- || true)

if [ -z "$PLAINTEXT" ]; then
  echo "❌ TRAEFIK_PLAINTEXT_PASSWORD not set in $ENV_FILE"
  exit 1
fi

# Generate hash and escape `$` for Docker Compose
HASHED=$(openssl passwd -apr1 "$PLAINTEXT" | sed 's/\$/$$/g')

if grep -q '^TRAEFIK_HASHED_PASSWORD=' "$ENV_FILE"; then
  sed -i "s/^TRAEFIK_HASHED_PASSWORD=.*/TRAEFIK_HASHED_PASSWORD=$HASHED/" "$ENV_FILE"
else
  echo "TRAEFIK_HASHED_PASSWORD=$HASHED" >> "$ENV_FILE"
fi

echo "✅ Updated TRAEFIK_HASHED_PASSWORD in $ENV_FILE"
echo "   Hashed password (escaped): $HASHED"
