#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="$(mktemp -d "${TMPDIR:-/tmp}/php-ci-static-runtime-assets.XXXXXX")"

# shellcheck source=scripts/runtime-assets.bash
source "$root/scripts/runtime-assets.bash"

cleanup() {
  rm -rf "$workspace"
}

trap cleanup EXIT

fail() {
  echo "::error::$1"
  exit 1
}

assert_file_equals() {
  local file="$1"
  local expected="$2"
  local actual

  actual="$(cat "$file")"
  [[ "$actual" == "$expected" ]] || fail "$file content mismatch"
}

assert_fails() {
  local message="$1"
  shift

  if "$@" >/dev/null 2>&1; then
    fail "$message"
  fi
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  [[ "$actual" == "$expected" ]] || fail "$message (expected '$expected', got '$actual')"
}

make_case() {
  local name="$1"

  case_dir="$workspace/$name"
  release="$case_dir/release"
  dist="$case_dir/dist"
  work="$case_dir/work"

  mkdir -p "$release" "$dist" "$work"
}

(
  brew() {
    [[ "$*" == 'info php@8.5' ]]
  }
  assert_equals 'php@8.5' "$(php_ci_static_homebrew_formula 8.5)" \
    'Prefer the versioned Homebrew formula when available'
)

(
  brew() {
    return 1
  }
  assert_equals 'php' "$(php_ci_static_homebrew_formula 8.5)" \
    'Use the default Homebrew formula when the versioned formula is absent'
)

write_runtime_assets() {
  printf 'php binary fixture\n' > "$release/php-linux-x86_64"
  printf 'pcov fixture\n' > "$release/pcov-linux-x86_64.so"
  printf 'xdebug fixture\n' > "$release/xdebug-linux-x86_64.so"
}

write_raw_checksums() {
  (
    cd "$release"
    sha256sum php-linux-x86_64 pcov-linux-x86_64.so xdebug-linux-x86_64.so > SHA256SUMS
  )
}

write_full_checksums() {
  (
    cd "$release"
    sha256sum \
      php-linux-x86_64 pcov-linux-x86_64.so xdebug-linux-x86_64.so \
      php-linux-x86_64.zst pcov-linux-x86_64.so.zst xdebug-linux-x86_64.so.zst \
      > SHA256SUMS
  )
}

compress_runtime_assets() {
  command -v zstd >/dev/null \
    || fail "zstd is required for runtime asset tests"

  zstd -q -f "$release/php-linux-x86_64"
  zstd -q -f "$release/pcov-linux-x86_64.so"
  zstd -q -f "$release/xdebug-linux-x86_64.so"
}

release_base() {
  printf 'file://%s' "$release"
}

test_raw_download_path() {
  make_case raw
  write_runtime_assets
  write_raw_checksums

  php_ci_static_download_asset "$(release_base)" "$release/SHA256SUMS" "$dist" "$work" php-linux-x86_64

  assert_file_equals "$dist/php-linux-x86_64" "php binary fixture"
}

test_zstd_download_path() {
  make_case zstd
  write_runtime_assets
  compress_runtime_assets
  write_full_checksums
  rm "$release/php-linux-x86_64"

  php_ci_static_download_asset "$(release_base)" "$release/SHA256SUMS" "$dist" "$work" php-linux-x86_64

  assert_file_equals "$dist/php-linux-x86_64" "php binary fixture"
}

test_corrupt_compressed_asset_fails() {
  make_case corrupt-zstd
  write_runtime_assets
  compress_runtime_assets
  write_full_checksums
  printf 'corrupt' >> "$release/php-linux-x86_64.zst"

  assert_fails \
    "corrupt compressed asset should fail before raw fallback" \
    php_ci_static_download_asset "$(release_base)" "$release/SHA256SUMS" "$dist" "$work" php-linux-x86_64
}

test_missing_checksum_entry_fails_without_exiting() {
  make_case missing-entry
  write_runtime_assets
  write_raw_checksums

  assert_fails \
    "missing checksum entry should return failure" \
    php_ci_static_verify_asset "$release/SHA256SUMS" "$release" missing-linux-x86_64
}

test_runtime_cache_ready_verifies_every_asset() {
  make_case cache-ready
  write_runtime_assets
  write_raw_checksums
  cp "$release/php-linux-x86_64" "$dist/php-linux-x86_64"
  cp "$release/pcov-linux-x86_64.so" "$dist/pcov-linux-x86_64.so"
  cp "$release/xdebug-linux-x86_64.so" "$dist/xdebug-linux-x86_64.so"

  php_ci_static_runtime_cache_is_ready "$release/SHA256SUMS" "$dist"

  printf 'corrupt\n' > "$dist/pcov-linux-x86_64.so"
  assert_fails \
    "corrupt cached asset should make runtime cache unready" \
    php_ci_static_runtime_cache_is_ready "$release/SHA256SUMS" "$dist"
}

test_runtime_cache_missing_checksum_returns_failure() {
  make_case cache-missing-checksum
  write_runtime_assets
  (
    cd "$release"
    sha256sum php-linux-x86_64 pcov-linux-x86_64.so > SHA256SUMS
  )
  cp "$release/php-linux-x86_64" "$dist/php-linux-x86_64"
  cp "$release/pcov-linux-x86_64.so" "$dist/pcov-linux-x86_64.so"
  cp "$release/xdebug-linux-x86_64.so" "$dist/xdebug-linux-x86_64.so"

  assert_fails \
    "runtime cache probe should return failure when SHA256SUMS is missing an asset" \
    php_ci_static_runtime_cache_is_ready "$release/SHA256SUMS" "$dist"
}

test_render_ini_values_renders_one_line_per_directive() {
  local out
  out="$(php_ci_static_render_ini_values 'memory_limit=512M, opcache.enable_cli=1')"

  assert_equals $'memory_limit=512M\nopcache.enable_cli=1' "$out" \
    "comma-separated directives should render one per line"
}

test_render_ini_values_keeps_comma_values_intact() {
  local out
  out="$(php_ci_static_render_ini_values 'disable_functions=exec,passthru, memory_limit=512M')"
  assert_equals $'disable_functions=exec,passthru\nmemory_limit=512M' "$out" \
    "unquoted commas inside a value should not split the directive"

  out="$(php_ci_static_render_ini_values 'disable_functions="exec,passthru"')"
  assert_equals 'disable_functions=exec,passthru' "$out" \
    "quoted commas inside a value should not split the directive"
}

test_render_ini_values_quotes_values_the_ini_lexer_would_mangle() {
  local out
  out="$(php_ci_static_render_ini_values "error_log='/tmp/foo=bar.log'")"

  assert_equals 'error_log="/tmp/foo=bar.log"' "$out" \
    "values containing = should be wrapped in double quotes"
}

test_render_ini_values_rejects_malformed_pair() {
  assert_fails \
    "a directive without = should be rejected" \
    php_ci_static_render_ini_values 'memory_limit'
}

test_resolve_release_base_reads_channel_pointer() {
  make_case pointer
  printf 'https://github.com/publicala/php-ci-static/releases/download/php-8.3.99\n' > "$case_dir/8.3"

  local out
  out="$(PHP_CI_STATIC_POINTER_BASE="file://$case_dir" php_ci_static_resolve_release_base 8.3)"

  assert_equals 'https://github.com/publicala/php-ci-static/releases/download/php-8.3.99' "$out" \
    "resolver should return the release base the pointer names"
}

test_resolve_release_base_rejects_series_mismatch() {
  make_case pointer-mismatch
  printf 'https://github.com/publicala/php-ci-static/releases/download/php-8.3.99\n' > "$case_dir/8.4"

  export PHP_CI_STATIC_POINTER_BASE="file://$case_dir"
  assert_fails \
    "a pointer naming a different PHP series should be rejected" \
    php_ci_static_resolve_release_base 8.4
  unset PHP_CI_STATIC_POINTER_BASE
}

test_resolve_release_base_falls_back_when_pointer_unreachable() {
  make_case pointer-missing

  local out
  out="$(PHP_CI_STATIC_POINTER_BASE="file://$case_dir/missing" php_ci_static_resolve_release_base 8.3 2>/dev/null)"

  assert_equals 'https://github.com/publicala/php-ci-static/releases/download/latest-8.3' "$out" \
    "an unreachable pointer should fall back to the frozen latest release"
}

test_php_probe_prepends_both_stdout_closing_flags() {
  make_case php-probe
  local stub="$case_dir/php-stub"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@"\n' > "$stub"
  chmod +x "$stub"

  local out
  out="$(php_ci_static_php_probe "$stub" -r 'echo 1;')"

  assert_equals $'-d\ndisplay_errors=stderr\n-d\nlog_errors=0\n-r\necho 1;' "$out" \
    "probe should run the given binary with both stdout-closing flags before caller arguments"
}

test_raw_download_path
test_zstd_download_path
test_corrupt_compressed_asset_fails
test_missing_checksum_entry_fails_without_exiting
test_runtime_cache_ready_verifies_every_asset
test_runtime_cache_missing_checksum_returns_failure
test_render_ini_values_renders_one_line_per_directive
test_render_ini_values_keeps_comma_values_intact
test_render_ini_values_quotes_values_the_ini_lexer_would_mangle
test_render_ini_values_rejects_malformed_pair
test_resolve_release_base_reads_channel_pointer
test_resolve_release_base_rejects_series_mismatch
test_resolve_release_base_falls_back_when_pointer_unreachable
test_php_probe_prepends_both_stdout_closing_flags

echo "runtime asset helper tests passed"
