# Changelog

## v1.2.0

- Composer is now always installed; the `composer` input from
  v1.1.0 has been removed. Every realistic CI job needs composer
  (composer install, vendor/bin/*, ad-hoc `composer show`), and
  the download is ~2-3s — gating it behind a knob was extra
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

- `uses: publicala/php-ci-static@v1` — one step replaces 6-9
  lines of curl + SHA256 + chmod boilerplate per CI job.
- Inputs: `php-version` (8.3 | 8.4 | 8.5, required) and
  `coverage` (none | pcov | xdebug, default `none`).
- Coverage drivers are auto-loaded via `PHP_INI_SCAN_DIR` so
  subsequent `php` calls see them without `-d` flags.
- Hardened SHA256 verification — the check fails loudly if the
  asset line is missing from `SHA256SUMS` (the default
  `sha256sum -c --ignore-missing` would silently pass).
- Linux x86_64 only; the action fails fast on other OS / arch.

## Versioning

- `1.0.x` — bug fix only; tag moves the sliding `v1`.
- `1.x.0` — backward-compatible input added; tag moves `v1`.
- `2.0.0` — breaking input change; new sliding `v2`; `v1`
  frozen.
