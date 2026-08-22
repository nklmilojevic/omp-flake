#!/usr/bin/env bash
set -euo pipefail

SOURCES_FILE="sources.json"
GITHUB_API_URL="https://api.github.com/repos/can1357/oh-my-pi/releases"
RELEASE_BASE_URL="https://github.com/can1357/oh-my-pi/releases/download"

# nix system -> release asset name. The glibc Linux artifacts are used rather
# than the musl ones: autoPatchelfHook can rewrite the glibc interpreter to the
# nixpkgs loader, while the musl builds hardcode /lib/ld-musl-*.so.1.
PLATFORMS="
x86_64-linux:omp-linux-x64
aarch64-linux:omp-linux-arm64
x86_64-darwin:omp-darwin-x64
aarch64-darwin:omp-darwin-arm64
"

get_latest_stable_version() {
  local headers=(-H "Accept: application/vnd.github+json" -H "User-Agent: omp-flake-updater")

  # Use GITHUB_TOKEN if available
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    headers+=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fi

  # Stable releases only, then sort by semantic version (highest first)
  curl -sL "${headers[@]}" "$GITHUB_API_URL?per_page=100" | jq -r '
    [.[] | select(.prerelease == false and .draft == false)
         | .tag_name
         | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
         | sub("^v"; "")]
    | sort_by(split(".") | map(tonumber))
    | reverse
    | first
  '
}

compute_sri_hash() {
  local url="$1"
  nix store prefetch-file "$url" --json 2>/dev/null | jq -r '.hash'
}

main() {
  echo "Checking for omp updates..."

  local current_version
  current_version=$(jq -r '.version' "$SOURCES_FILE")
  echo "Current version: $current_version"

  local latest_version
  latest_version=$(get_latest_stable_version)

  if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
    echo "Error: Failed to get latest version"
    exit 1
  fi

  echo "Latest stable version: $latest_version"

  if [[ "$current_version" == "$latest_version" ]]; then
    echo "Already at latest version, no update needed"
    exit 0
  fi

  echo "Updating from $current_version to $latest_version..."

  local platforms_json="{}"

  for entry in $PLATFORMS; do
    local nix_platform="${entry%%:*}"
    local asset="${entry##*:}"
    local url="$RELEASE_BASE_URL/v${latest_version}/${asset}"

    echo "Fetching hash for $nix_platform..."

    local hash
    hash=$(compute_sri_hash "$url")

    if [[ -z "$hash" || "$hash" == "null" ]]; then
      echo "Error: Failed to compute hash for $nix_platform"
      exit 1
    fi

    echo "  $nix_platform: $hash"

    platforms_json=$(echo "$platforms_json" | jq \
      --arg platform "$nix_platform" \
      --arg url "$url" \
      --arg hash "$hash" \
      '. + {($platform): {"url": $url, "hash": $hash}}')
  done

  jq -n \
    --arg version "$latest_version" \
    --argjson platforms "$platforms_json" \
    '{"version": $version, "platforms": $platforms}' > "$SOURCES_FILE"

  echo "Successfully updated sources.json to version $latest_version"
}

main "$@"
