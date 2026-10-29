#!/usr/bin/env bash

# Print the newest released patch for a PHP series (e.g. 8.4 -> 8.4.27),
# as published by php.net. Returns non-zero when php.net is unreachable or
# answers with anything other than a patch of the requested series.
php_ci_static_latest_patch() {
  local series="$1"
  local version

  version="$(curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL \
    "https://www.php.net/releases/index.php?json&version=${series}" \
    | jq -r '.version // empty' 2>/dev/null || true)"

  if [[ ! "$version" =~ ^${series//./\\.}\.[0-9]+$ ]]; then
    echo "::error::php.net did not return a patch release for PHP ${series} (got '${version}')" >&2
    return 1
  fi

  printf '%s\n' "$version"
}

php_ci_static_release_is_published() {
  local tag="$1"

  [[ "$(gh release view "$tag" --json isDraft --jq '.isDraft' 2>/dev/null)" == "false" ]]
}

# Print the build matrix as a JSON array of {series, version} objects. A
# scheduled run builds only the series whose newest patch has no published
# release yet, so it can poll often and stay idle between PHP releases.
# Any other event rebuilds every series to validate the build config.
php_ci_static_build_matrix() {
  local event="$1"
  shift
  local series version
  local entries=()

  for series in "$@"; do
    version="$(php_ci_static_latest_patch "$series")" || return 1

    if [[ "$event" == "schedule" ]] && php_ci_static_release_is_published "php-${version}"; then
      echo "PHP ${version} is already published. Skipping the ${series} build." >&2
      continue
    fi

    entries+=("$(jq -cn --arg series "$series" --arg version "$version" '{series: $series, version: $version}')")
  done

  if (( ${#entries[@]} == 0 )); then
    echo '[]'
    return
  fi

  printf '%s\n' "${entries[@]}" | jq -cs '.'
}
