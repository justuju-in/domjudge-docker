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

# Generate hash
HASHED_RAW=$(openssl passwd -apr1 "$PLAINTEXT")

# Escape dollar signs by doubling them so Docker Compose won't try to expand $apr1 etc.
HASHED_ESCAPED=$(printf '%s' "$HASHED_RAW" | sed 's/\$/\$\$/g')

# Safely replace or append the TRAEFIK_HASHED_PASSWORD line using awk (handles arbitrary characters)
tmpfile=$(mktemp)
awk -v val="$HASHED_ESCAPED" '
  BEGIN { found=0 }
  /^TRAEFIK_HASHED_PASSWORD=/ { print "TRAEFIK_HASHED_PASSWORD=" val; found=1; next }
  { print }
  END { if (!found) print "TRAEFIK_HASHED_PASSWORD=" val }
' "$ENV_FILE" > "$tmpfile" && mv "$tmpfile" "$ENV_FILE"

echo "✅ Updated TRAEFIK_HASHED_PASSWORD in $ENV_FILE"
echo "   Hashed password (escaped): $HASHED"
