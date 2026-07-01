# Changelog

## v1.8.0

- Add `scripts/install-php.bash`, a standalone installer for environments
  outside GitHub Actions (dev containers, Forge, raw shell). It resolves
  the channel pointer, downloads and checksum-verifies the binary, installs
  it onto `PATH`, and renders optional `--ini-values` into the binary's
  compiled-in ini scan dir (`/usr/local/etc/php/conf.d`), so directives
  apply without `PHP_INI_SCAN_DIR` plumbing. Fetch it together with its
  sibling `runtime-assets.bash` from the same ref.

- Extract the channel-pointer resolution and the `ini-values`
  parser/renderer from the composite action into shared functions in
  `scripts/runtime-assets.bash` (`php_ci_static_resolve_release_base`,
  `php_ci_static_render_ini_values`), used by both the action and the new
  installer. The parser was previously duplicated inside `action.yml`.
  Action behavior is unchanged; warnings and errors still surface as
  workflow annotations inside Actions and print as plain text elsewhere.

## v1.7.0

- Add a runtime asset cache to the root action. The action now resolves
  the concrete `php-X.Y.Z` release, downloads a fresh `SHA256SUMS`, and
  restores the PHP binary plus both coverage modules from the consuming
  repository's GitHub Actions cache when the cached files verify against
  that checksum. Cache misses download and verify the release assets,
  then save immediately with `actions/cache/save@v5`, so a seed job can
  populate fan-out jobs before the job ends. The root action now exposes
  `runtime-cache-hit` for diagnostics. Cache restore/save failures stay
  non-fatal, but now emit explicit warnings before falling back to
  release downloads.

- Publish `.zst` copies of the PHP binary and coverage modules for new
  immutable PHP releases. The action uses them automatically when `zstd`
  is available and falls back to raw assets for old raw-only releases or
  runners without `zstd`. Raw assets remain published for compatibility.

- Keep existing immutable PHP releases idempotent. Rebuilds of an
  already-published patch still require the original raw assets and
  `SHA256SUMS`, but missing `.zst` assets only warn because immutable
  releases cannot be amended after publish.

- Add deterministic Bash tests for the runtime asset helpers, covering
  raw downloads, `.zst` downloads, corrupt assets, missing checksum
  entries, and cache-ready verification.

## v1.6.1

- Resolve binaries through a channel pointer instead of the sliding
  `latest-8.x` releases. The organization now enforces immutable GitHub
  Releases, so the old model (overwrite the `latest-8.x` assets on every
  build) no longer works. Builds now publish one immutable release per
  PHP patch (`php-8.4.21`) and update a mutable per-series pointer on the
  `channels` branch. The action reads the pointer to find the current
  binary, and falls back to the frozen `latest-8.x` release if the
  pointer is unreachable.

  The channel only ever advances. A rebuild or re-run that produces an
  older patch leaves the pointer unchanged, so `@v1` consumers are never
  downgraded to an earlier PHP build.

  Backward-compatible. Consumers on `@v1` (root action or
  `setup-php-vendor`) need no changes, and the action's inputs are
  unchanged. Hand-rolled `latest-8.x` download URLs keep returning the
  last assets published before immutability. Switch them to the pointer
  (see the README "Manual install" section) to get fresh binaries.

## v1.5.2

- Style pass across the repo docs and comments. Straighten
  em dashes, drop prose semicolons, and cut filler words.
  The `ini-values` input description (shown in the Actions
  UI) is reworded into plain sentences. No functional change.

## v1.5.1

- Set `memory_limit=-1` as a baseline ini default in the composite
  action's scan dir. The static binary's compiled-in default is
  `memory_limit=128M` (the upstream `php.ini-*` template value, tuned
  for shared-hosting web SAPIs), but Ubuntu's php-cli ships
  `memory_limit=-1` and every realistic CI workload (PHPCS, PHPStan,
  PHPUnit on Laravel-sized codebases) exceeds 128M. The 128M default
  surfaced as PHPCS silently exiting 255 mid-run on consumers like
  `tightenco/duster`, which wraps PHPCS in `ob_start()`. The OOM fatal
  was buffered and never flushed, leaving CI logs cut off after the
  "Linting using PHP_CodeSniffer" banner with no visible error.

  The baseline ini is loaded first by alphabetical scan order
  (`00-ci-defaults.ini`), so user `ini-values` (`custom.ini`) and
  `coverage` (`coverage.ini`) still win. `ini-values: memory_limit=512M`
  keeps doing exactly what it always did. `PHP_INI_SCAN_DIR` is now
  exported on every run (previously only when `coverage` or
  `ini-values` was set). Non-breaking.

## v1.5.0

- Add sibling composite `publicala/php-ci-static/setup-php-vendor@v1`.
  One step that installs the static PHP CLI (via the root action) and
  restores a Composer vendor cache populated by an upstream seed job.
  Intended for fan-out CI topologies. One build job seeds `vendor/`
  once, many consumer jobs (lint, static analysis, tests) read it back
  without re-running `composer install`. Read-only by design. The
  caller saves the cache from the seed job using the exposed
  `cache-key` output, so producer and consumer keys cannot drift.

  Inputs: `php-version`, `coverage`, `ini-values` (all forwarded to
  the root action), `dependency-path` (multi-line glob list, default
  `composer.json` + `composer.lock`), `fail-on-cache-miss` (default
  `'true'`, a missing cache fails the step, pointing the operator at
  the seed job instead of producing a vendor-less binary later).

  Outputs: `cache-hit` (true on exact match) and `cache-key`
  (`composer-<runner.os>-php-<version>-<hash>`).

  Non-breaking. The root `publicala/php-ci-static@v1` action is
  unchanged.

## v1.4.0

- Add `ini-values` input. Pass comma- or newline-separated `key=value`
  pairs to set arbitrary php.ini directives (`memory_limit=512M,
  opcache.enable_cli=1`, etc.) without writing files into the
  action's internal scan dir. Mirrors `shivammathur/setup-php`'s
  `ini-values` shape, including quoted values for commas inside
  values (`disable_functions="exec,passthru"`). Also accepts the
  bare form (`disable_functions=exec,passthru`). The parser only
  treats a comma as a separator when it precedes a `<directive>=`,
  which setup-php itself does not. Composes with `coverage:` (both
  load from the same `PHP_INI_SCAN_DIR`). Directive names are
  validated, so a typo fails the step instead of producing a
  silently-ignored ini file. Non-breaking.

## v1.3.0

- Static PHP binaries now include `imagick`. This keeps Laravel CI jobs
  that require `ext-imagick` on the static PHP path instead of falling
  back to a container.

## v1.2.0

- Composer is now always installed. The `composer` input from
  v1.1.0 has been removed. Every realistic CI job needs composer
  (composer install, vendor/bin/*, ad-hoc `composer show`), and
  the download is ~2-3s. Gating it behind a knob was extra
  surface area for no benefit. Existing callers that still pass
  `composer: true` will see a one-time "Unexpected input"
  warning from GH Actions but otherwise keep working unchanged.

## v1.1.0

- Add `composer` input (default `false`). When `true`, the action
  downloads `composer-stable.phar` and puts `composer` on
  `PATH` alongside `php`. Replaces the 4-line inline curl recipe
  consumers (and the pla-stack audit) used to inject after the
  PHP install. Non-breaking.

## v1.0.0

First release of the composite action.

- `uses: publicala/php-ci-static@v1`: one step replaces 6-9
  lines of curl + SHA256 + chmod boilerplate per CI job.
- Inputs: `php-version` (8.3 | 8.4 | 8.5, required) and
  `coverage` (none | pcov | xdebug, default `none`).
- Coverage drivers are auto-loaded via `PHP_INI_SCAN_DIR` so
  subsequent `php` calls see them without `-d` flags.
- Hardened SHA256 verification. The check fails loudly if the
  asset line is missing from `SHA256SUMS` (the default
  `sha256sum -c --ignore-missing` would silently pass).
- Linux x86_64 only. The action fails fast on other OS / arch.

## Versioning

- `1.0.x`: bug fix only. Tag moves the sliding `v1`.
- `1.x.0`: backward-compatible input added. Tag moves `v1`.
- `2.0.0`: breaking input change. New sliding `v2`, `v1`
  frozen.
