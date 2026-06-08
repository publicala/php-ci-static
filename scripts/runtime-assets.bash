#!/usr/bin/env bash

php_ci_static_checksum_line() {
  local checksum_file="$1"
  local name="$2"

  awk -v name="$name" '
    $1 ~ /^[0-9a-f]{64}$/ && $2 == name { print; found = 1; exit }
    END { if (! found) exit 1 }
  ' "$checksum_file"
}

php_ci_static_verify_asset() {
  local checksum_file="$1"
  local directory="$2"
  local name="$3"
  local line

  if ! line="$(php_ci_static_checksum_line "$checksum_file" "$name")"; then
    echo "::error::SHA256SUMS missing entry for ${name}"
    return 1
  fi

  (cd "$directory" && printf '%s\n' "$line" | sha256sum -c -)
}

php_ci_static_runtime_cache_is_ready() {
  local checksum_file="$1"
  local dist="$2"
  local asset

  for asset in php-linux-x86_64 pcov-linux-x86_64.so xdebug-linux-x86_64.so; do
    [[ -f "$dist/$asset" ]] || return 1
  done

  for asset in php-linux-x86_64 pcov-linux-x86_64.so xdebug-linux-x86_64.so; do
    php_ci_static_verify_asset "$checksum_file" "$dist" "$asset" >/dev/null 2>&1 || return 1
  done
}

php_ci_static_download_asset() {
  local base="$1"
  local checksum_file="$2"
  local dist="$3"
  local work="$4"
  local name="$5"
  local compressed="${name}.zst"

  if command -v zstd >/dev/null 2>&1 && php_ci_static_checksum_line "$checksum_file" "$compressed" >/dev/null 2>&1; then
    if curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL \
      -o "$work/$compressed" "$base/$compressed"; then
      php_ci_static_verify_asset "$checksum_file" "$work" "$compressed" || return 1
      zstd -q -d -c "$work/$compressed" > "$dist/$name" || return 1
      php_ci_static_verify_asset "$checksum_file" "$dist" "$name" || return 1
      return 0
    fi

    echo "::warning::could not download ${compressed}. Falling back to ${name}."
  fi

  curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL \
    -o "$dist/$name" "$base/$name" || return 1
  php_ci_static_verify_asset "$checksum_file" "$dist" "$name"
}

php_ci_static_download_runtime_assets() {
  local base="$1"
  local checksum_file="$2"
  local dist="$3"
  local work="$4"

  php_ci_static_download_asset "$base" "$checksum_file" "$dist" "$work" php-linux-x86_64
  php_ci_static_download_asset "$base" "$checksum_file" "$dist" "$work" pcov-linux-x86_64.so
  php_ci_static_download_asset "$base" "$checksum_file" "$dist" "$work" xdebug-linux-x86_64.so
  cp "$checksum_file" "$dist/SHA256SUMS"
}
