#!/usr/bin/env bash
# arr-migrate.sh — Migrate all Sonarr/Radarr content to the configured quality profile
# and remove any leftover profiles.
#
# Uses the bulk editor API, so the entire library is migrated in two API calls
# regardless of how many items exist.
#
# Run this after the Ansible playbook has applied the profile configuration.
#
# Usage:
#   ./arr-migrate.sh           # migrate both Sonarr and Radarr
#   ./arr-migrate.sh sonarr    # migrate Sonarr only
#   ./arr-migrate.sh radarr    # migrate Radarr only
#
# Requires: curl, jq

set -euo pipefail

# ── Configuration (override via environment variables) ────────────────────────
SONARR_URL="${SONARR_URL:-http://localhost:8989}"
SONARR_API_KEY="${SONARR_API_KEY:-your-sonarr-api-key}"

RADARR_URL="${RADARR_URL:-http://localhost:7878}"
RADARR_API_KEY="${RADARR_API_KEY:-your-radarr-api-key}"

PROFILE_NAME="${PROFILE_NAME:-Custom 720/1080p}"
BATCH_SIZE="${BATCH_SIZE:-100}"

# ── Prereq check ──────────────────────────────────────────────────────────────
for cmd in curl jq; do
  command -v "$cmd" &>/dev/null || { echo "Error: $cmd is required but not installed." >&2; exit 1; }
done

# ── Helpers ───────────────────────────────────────────────────────────────────
arr_get() {
  # arr_get <url> <api_key> <path>
  curl -sf -H "X-Api-Key: $2" "$1/api/v3$3"
}

arr_put() {
  # arr_put <url> <api_key> <path> <body>
  curl -sf -X PUT -H "X-Api-Key: $2" -H "Content-Type: application/json" -d "$4" "$1/api/v3$3"
}

arr_delete() {
  # arr_delete <url> <api_key> <path>
  curl -sf -X DELETE -H "X-Api-Key: $2" "$1/api/v3$3" || true
}

# ── Migration ─────────────────────────────────────────────────────────────────
migrate() {
  local label="$1" url="$2" api_key="$3" content_type="$4" ids_field="$5"

  echo "[$label] Connecting to $url..."

  # Resolve profile ID by name
  local profiles profile_id
  profiles=$(arr_get "$url" "$api_key" "/qualityprofile")
  profile_id=$(echo "$profiles" | jq -r --arg name "$PROFILE_NAME" '.[] | select(.name == $name) | .id')

  if [[ -z "$profile_id" ]]; then
    echo "[$label] Error: profile '$PROFILE_NAME' not found — run the Ansible playbook first." >&2
    return 1
  fi

  echo "[$label] Target profile: '$PROFILE_NAME' (id $profile_id)"

  # Find all items not already on the target profile
  local content ids_to_migrate count
  content=$(arr_get "$url" "$api_key" "/$content_type")
  ids_to_migrate=$(echo "$content" | jq --argjson pid "$profile_id" '[.[] | select(.qualityProfileId != $pid) | .id]')
  count=$(echo "$ids_to_migrate" | jq 'length')

  if [[ "$count" -eq 0 ]]; then
    echo "[$label] All $content_type already on '$PROFILE_NAME', nothing to migrate."
  else
    local batches=$(( (count + BATCH_SIZE - 1) / BATCH_SIZE ))
    echo "[$label] Migrating $count $content_type to '$PROFILE_NAME' ($batches batch(es) of up to $BATCH_SIZE)..."
    local batch=0
    while [[ $batch -lt $batches ]]; do
      local offset=$(( batch * BATCH_SIZE ))
      local chunk
      chunk=$(echo "$ids_to_migrate" | jq ".[$offset:$((offset + BATCH_SIZE))]")
      local chunk_size
      chunk_size=$(echo "$chunk" | jq 'length')
      echo "[$label]   batch $((batch + 1))/$batches — $chunk_size items..."
      arr_put "$url" "$api_key" "/$content_type/editor" \
        "{\"${ids_field}\": $chunk, \"qualityProfileId\": $profile_id}" > /dev/null
      batch=$(( batch + 1 ))
    done
    echo "[$label] Migration complete."
  fi

  # Remove any profiles that are no longer in use
  local profiles_after unused
  profiles_after=$(arr_get "$url" "$api_key" "/qualityprofile")
  unused=$(echo "$profiles_after" | jq -r --argjson pid "$profile_id" '.[] | select(.id != $pid) | "\(.id) \(.name)"')

  if [[ -z "$unused" ]]; then
    echo "[$label] No unused profiles to remove."
  else
    echo "$unused" | while read -r id name; do
      echo "[$label] Deleting unused profile: '$name' (id $id)"
      arr_delete "$url" "$api_key" "/qualityprofile/$id" > /dev/null
    done
  fi
}

# ── Entry point ───────────────────────────────────────────────────────────────
TARGET="${1:-both}"

case "$TARGET" in
  sonarr) migrate "Sonarr" "$SONARR_URL" "$SONARR_API_KEY" "series" "seriesIds" ;;
  radarr) migrate "Radarr" "$RADARR_URL" "$RADARR_API_KEY" "movie"  "movieIds"  ;;
  both)
    migrate "Sonarr" "$SONARR_URL" "$SONARR_API_KEY" "series" "seriesIds"
    migrate "Radarr" "$RADARR_URL" "$RADARR_API_KEY" "movie"  "movieIds"
    ;;
  *)
    echo "Usage: $0 [sonarr|radarr|both]" >&2
    exit 1
    ;;
esac
