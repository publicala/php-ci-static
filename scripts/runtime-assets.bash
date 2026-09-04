#!/usr/bin/env bash

php_ci_static_homebrew_formula() {
  local php_version="$1"

  if brew info "php@${php_version}" >/dev/null 2>&1; then
    echo "php@${php_version}"
    return
  fi

  echo php
}

php_ci_static_install_composer() {
  local bin="$1"

  mkdir -p "$bin"
  curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL \
    -o "$bin/composer" https://getcomposer.org/composer-stable.phar
  chmod +x "$bin/composer"
  echo "$bin" >> "$GITHUB_PATH"
  export PATH="$bin:$PATH"
}

php_ci_static_diagnostics() {
  echo "::group::php -v"
  php -v
  echo "::endgroup::"
  echo "::group::php -m"
  php -m
  echo "::endgroup::"
  echo "::group::php --ini"
  php --ini
  echo "::endgroup::"
  echo "::group::composer --version"
  composer --version
  echo "::endgroup::"
}

# Emit as GitHub workflow annotations inside Actions, plain text elsewhere,
# so the same helpers serve the composite action and install-php.bash.
php_ci_static_warn() {
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "::warning::$1" >&2
  else
    echo "Warning: $1" >&2
  fi
}

php_ci_static_error() {
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "::error::$1" >&2
  else
    echo "Error: $1" >&2
  fi
}

# Run a PHP binary for a captured probe (`$(...)`), keeping startup
# diagnostics off stdout so the substitution reads the value alone. Startup
# diagnostics are ordinary E_WARNINGs, and PHP has two independent routes for
# putting one on stdout, both of which have to be closed or the warning lands
# inside the captured value: display_errors defaults to STDOUT on CLI (pinned
# to stderr), and log_errors writes a second copy to error_log, which
# ini-values can point at /dev/stdout (switched off). The reachable trigger:
# a coverage extension overrides zend_execute_ex, so requesting opcache.jit
# through ini-values makes PHP disable the JIT and warn while doing it. The
# flags are scoped to the one invocation, so the diagnostics still reach the
# log on stderr and the caller's own directives are untouched. First argument
# is the php binary (callers probe before PATH picks it up), the rest are
# passed through.
php_ci_static_php_probe() {
  local php_bin="$1"
  shift
  "$php_bin" -d display_errors=stderr -d log_errors=0 "$@"
}

# Resolve the current immutable release for a PHP series from the channel
# pointer. The organization enforces immutable releases, so binaries ship as
# one release per patch (php-X.Y.Z) and the pointer names the newest. Falls
# back to the frozen latest-X.Y release if the pointer cannot be reached, so
# a transient raw.githubusercontent outage still yields a working,
# checksum-verified binary. Prints the release base URL on stdout.
# PHP_CI_STATIC_POINTER_BASE overrides the pointer location (tests, forks).
php_ci_static_resolve_release_base() {
  local php_version="$1"
  local pointer_base="${PHP_CI_STATIC_POINTER_BASE:-https://raw.githubusercontent.com/publicala/php-ci-static/channels}"
  local pointer="${pointer_base}/${php_version}"
  local base

  # tr strips a trailing CR or stray whitespace so a pointer hand-edited via
  # the GitHub web UI (which writes CRLF) does not slip a \r into the URL.
  base="$(curl --retry 3 --retry-delay 2 --retry-all-errors -fsSL "$pointer" 2>/dev/null | head -n1 | tr -d '[:space:]' || true)"
  if [[ -z "$base" ]]; then
    # The pointer was unreachable (a transient raw.githubusercontent outage,
    # or a deleted/empty channels/<series> file). Fall back to the frozen
    # pre-immutability release so the caller still gets a checksum-verified
    # binary, and warn that a persistent failure means a stale install.
    php_ci_static_warn "could not resolve channel pointer ${pointer}. Falling back to the frozen latest-${php_version} release, so the installed PHP may be an older patch. If this repeats, check that channels/${php_version} exists and is reachable."
    base="https://github.com/publicala/php-ci-static/releases/download/latest-${php_version}"
  fi

  # Constrain the base to this repo's release downloads for the requested
  # series. A pointer that resolves anywhere else, or to a different PHP
  # series (e.g. channels/8.4 pointing at php-8.3.x), is rejected rather
  # than fetched. Callers also assert the installed binary's version.
  local dl="https://github.com/publicala/php-ci-static/releases/download"
  case "$base" in
    "$dl/php-${php_version}."*) ;;
    "$dl/latest-${php_version}") ;;
    *)
      php_ci_static_error "resolved release base does not match php-version ${php_version}: ${base}"
      return 1
      ;;
  esac

  printf '%s\n' "$base"
}

# Parse an ini-values input string and print one rendered `key=value` php.ini
# line per directive on stdout. Returns non-zero on a malformed pair, so
# callers can validate with stdout discarded or render straight into an ini
# file. Two-pass parser:
#   1. awk treats `'` / `"` as quote delimiters ONLY when they sit at
#      "value-start" position (right after `=`, optionally past whitespace).
#      Quotes appearing later in a value are kept literal, so
#      `error_log=/tmp/o'reilly.log` stays intact. Inside a quoted value,
#      commas are replaced with \001 and the surrounding quote chars are
#      stripped.
#   2. sed splits on commas that precede a `<directive>=`, so the unquoted
#      form (`disable_functions=exec,passthru`) also stays one entry.
#      Newlines are separators too (YAML multiline).
# The \001 sentinel is restored to a literal comma before rendering.
php_ci_static_render_ini_values() {
  local ini_values="$1"
  local split raw pair key val

  split="$(printf '%s\n' "$ini_values" \
    | awk '
      BEGIN { sq = sprintf("%c", 39); dq = sprintf("%c", 34); s = sprintf("%c", 1) }
      {
        out = ""; q = ""; at_val_start = 0; n = length($0)
        for (i = 1; i <= n; i++) {
          c = substr($0, i, 1)
          if (q != "") {
            if (c == q) { q = ""; at_val_start = 0; continue }
            if (c == ",") c = s
            out = out c
            continue
          }
          if (at_val_start) {
            if (c == sq || c == dq) { q = c; at_val_start = 0; continue }
            if (c == " " || c == "\t") { out = out c; continue }
            out = out c; at_val_start = 0; continue
          }
          out = out c
          if (c == "=") at_val_start = 1
        }
        print out
      }' \
    | sed -E 's/,[[:space:]]*([A-Za-z_][A-Za-z0-9_.]*=)/\n\1/g')"

  while IFS= read -r raw; do
    pair="$(echo "$raw" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [[ -z "$pair" ]] && continue
    if [[ ! "$pair" =~ ^[A-Za-z_][A-Za-z0-9_.]*= ]]; then
      # Restore sentinel commas so the error message shows the input as the
      # user wrote it (minus the stripped quote chars).
      php_ci_static_error "ini-values: expected '<directive>=<value>' but got '${pair//$'\001'/,}'"
      return 1
    fi

    key="${pair%%=*}"
    val="$(echo "${pair#*=}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    val="${val//$'\001'/,}"
    # PHP's ini parser truncates unquoted values on `=` and treats `;` / `#`
    # as inline comment markers. `'` opens a single-quoted string in PHP's
    # ini lexer too, so values like `/tmp/o'reilly.log` get cut to `/tmp/o`
    # unless wrapped. Wrap in double quotes when any of those appear, plus
    # when the value contains a `"` itself (escaped via \"). Plain values,
    # commas, whitespace, and PHP-constant bitmask expressions like
    # `E_ALL & ~E_NOTICE` are left unquoted so PHP still evaluates them.
    if [[ "$val" == *=*       || "$val" == *';'*    \
       || "$val" == *'#'*     || "$val" == *'"'*    \
       || "$val" == *"'"* ]]; then
      val="\"${val//\"/\\\"}\""
    fi
    printf '%s=%s\n' "$key" "$val"
  done <<< "$split"
}

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
    php_ci_static_error "SHA256SUMS missing entry for ${name}"
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

    php_ci_static_warn "could not download ${compressed}. Falling back to ${name}."
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
