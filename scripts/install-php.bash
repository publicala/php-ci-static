#!/usr/bin/env bash
# Standalone installer for the publicala/php-ci-static static PHP CLI.
#
# For environments outside GitHub Actions: dev containers, Forge, raw shell.
# (Inside Actions, use the composite action; it adds runtime caching this
# script does not need.) Resolves the current release for a PHP series from
# the channels pointer, downloads and checksum-verifies the binary, installs
# it onto PATH, and renders optional php.ini directives into the binary's
# ini scan dir, so they apply to every subsequent `php` invocation with no
# environment plumbing.
#
# Usage:
#   install-php.bash --php-version <8.3|8.4|8.5> \
#     [--ini-values 'memory_limit=512M, opcache.enable_cli=1'] \
#     [--bin-dir /usr/local/bin] \
#     [--conf-dir /usr/local/etc/php/conf.d]
#
# The script sources its sibling runtime-assets.bash, so run it from a
# checkout, or fetch both files from the same ref:
#
#   base=https://raw.githubusercontent.com/publicala/php-ci-static/v1/scripts
#   curl -fsSL -O "$base/runtime-assets.bash"
#   curl -fsSL -O "$base/install-php.bash"
#   bash install-php.bash --php-version 8.3
#
# The default --conf-dir is the scan dir compiled into the static binary
# (`php --ini` reports it), so drop-ins load without PHP_INI_SCAN_DIR. A
# baseline memory_limit=-1 is written there on every run, because the
# binary's compiled-in 128M default is tuned for shared-hosting web SAPIs
# and OOMs real CLI workloads (composer, PHPStan, test suites). --ini-values
# render into a later-sorted file, so they win over the baseline.
#
# Coverage modules (pcov, xdebug) and composer are out of scope here: both
# ship separately (see the README's manual install section for the .so
# recipe), and every target this script is for already manages composer.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/runtime-assets.bash
source "$script_dir/runtime-assets.bash"

usage() {
  cat <<'USAGE'
Usage:
  install-php.bash --php-version <8.3|8.4|8.5> \
    [--ini-values 'memory_limit=512M, opcache.enable_cli=1'] \
    [--bin-dir /usr/local/bin] \
    [--conf-dir /usr/local/etc/php/conf.d]
USAGE
}

php_version=''
ini_values=''
bin_dir='/usr/local/bin'
conf_dir='/usr/local/etc/php/conf.d'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --php-version) php_version="${2:-}"; shift 2 ;;
    --ini-values) ini_values="${2:-}"; shift 2 ;;
    --bin-dir) bin_dir="${2:-}"; shift 2 ;;
    --conf-dir) conf_dir="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      php_ci_static_error "unknown argument: $1"
      usage >&2
      exit 1
      ;;
  esac
done

case "$php_version" in
  8.3|8.4|8.5) ;;
  *)
    php_ci_static_error "--php-version must be one of 8.3, 8.4, 8.5 (got '${php_version}')"
    exit 1
    ;;
esac

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  php_ci_static_error "publicala/php-ci-static only ships Linux x86_64 binaries (got $(uname -s)/$(uname -m))"
  exit 1
fi

if [[ -n "$ini_values" ]]; then
  # Validate before any download so a malformed directive fails fast.
  php_ci_static_render_ini_values "$ini_values" >/dev/null
fi

base="$(php_ci_static_resolve_release_base "$php_version")"
tag="${base##*/}"
echo "Installing static PHP ${php_version} from ${tag}."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL \
  -o "$work/SHA256SUMS" "$base/SHA256SUMS"
php_ci_static_download_asset "$base" "$work/SHA256SUMS" "$work" "$work" php-linux-x86_64

mkdir -p "$bin_dir" "$conf_dir"
install -m 0755 "$work/php-linux-x86_64" "$bin_dir/php"

printf 'memory_limit=-1\n' > "$conf_dir/00-php-ci-static-defaults.ini"
# Remove any custom ini a previous run wrote, so re-running without
# --ini-values does not keep applying the old directives.
rm -f "$conf_dir/99-php-ci-static-custom.ini"
if [[ -n "$ini_values" ]]; then
  php_ci_static_render_ini_values "$ini_values" > "$conf_dir/99-php-ci-static-custom.ini"
fi

if [[ -n "${PHP_INI_SCAN_DIR:-}" && "${PHP_INI_SCAN_DIR}" != "$conf_dir" ]]; then
  php_ci_static_warn "PHP_INI_SCAN_DIR is set to ${PHP_INI_SCAN_DIR}, which overrides the binary's compiled-in scan dir. The ini files written to ${conf_dir} will not load until it is unset or pointed there."
fi

# Assert the installed binary is the requested series, regardless of how the
# base resolved. Catches a mispointed channel or a wrong-series fallback
# before the caller runs anything against the wrong PHP.
#
# display_errors=stderr keeps startup diagnostics out of the captured value.
# PHP CLI defaults display_errors to STDOUT and startup diagnostics are
# ordinary E_WARNINGs, so one would otherwise prefix the version and fail this
# assert with "installed PHP X.Y does not match requested --php-version X.Y".
# Reachable straight from this script's own --ini-values: request opcache.jit
# while an extension that overrides zend_execute_ex is loaded and PHP disables
# the JIT and warns. Errors still reach the terminal, just on stderr.
installed="$("$bin_dir/php" -d display_errors=stderr -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')"
if [[ "$installed" != "$php_version" ]]; then
  php_ci_static_error "installed PHP ${installed} does not match requested --php-version ${php_version}"
  exit 1
fi

# Same reason as above: a startup warning would otherwise take the `head -n1`
# slot and report itself as the installed version.
echo "Installed $("$bin_dir/php" -d display_errors=stderr -v | head -n1) at ${bin_dir}/php (ini scan dir: ${conf_dir})."
