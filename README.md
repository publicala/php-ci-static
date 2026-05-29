# php-ci-static

Static PHP binaries for PLA CI. Built with [static-php-cli](https://github.com/crazywhalecc/static-php-cli), tuned to cover what Laravel apps actually need, and shipped behind a composite GitHub Action so consumers install PHP with one `uses:` step.

## Quick start

```yaml
- uses: publicala/php-ci-static@v1
  with:
    php-version: '8.4'
    coverage: pcov           # optional, default: none
```

That's it. The action downloads the static PHP binary for the matching `latest-8.4` release, verifies the checksum, puts both `php` and `composer` on `PATH`, and (if `coverage` is set) auto-loads the coverage driver via `PHP_INI_SCAN_DIR` so subsequent `php` calls just work.

## Development

```bash
npm install
npm test
npm run hooks:install
```

`npm test` runs the local tooling harness used in CI: Prettier for repo tooling files, `github-actionlint` for workflow files, and ShellCheck for embedded Bash in workflows and composite actions.

## Inputs

| Input | Required | Default | Accepted values |
|-------|----------|---------|-----------------|
| `php-version` | yes | — | `8.3`, `8.4`, `8.5` |
| `coverage` | no | `none` | `none`, `pcov`, `xdebug` |
| `ini-values` | no | `''` | Comma-separated `key=value` pairs |

When `coverage: xdebug`, the action sets `xdebug.mode=coverage` (mirroring `shivammathur/setup-php`). Override inline with `php -d xdebug.mode=...` for step-debugging or other modes.

The action also drops a baseline `memory_limit=-1` into the scan dir on every run, so CI workloads (PHPCS, PHPStan, PHPUnit on Laravel-sized codebases) don't hit the static binary's compiled-in 128M default. Override with `ini-values: memory_limit=512M` (or any other value) if you want a cap.

`ini-values` accepts php.ini directives, comma- or newline-separated — e.g. `memory_limit=512M, opcache.enable_cli=1`. Two ways to handle commas inside values: wrap the value in single or double quotes (`disable_functions="exec,passthru"`, matching `shivammathur/setup-php`), or rely on the smart-split fallback that treats a comma as a separator only when it precedes a `<directive>=` (so unquoted `disable_functions=exec,passthru` also works). Quote when the value contains `key=value`-shaped substrings (`error_log='/tmp/foo=bar.log'`). Composes with `coverage:`; both write into the same scan dir and load together.

Composer (stable) is always installed alongside `php`. It's a ~2-3s download and every realistic CI job needs it, so there's no opt-out.

## Examples

### Default (no coverage, fastest)

The static binary covers the common Laravel CI workload — lint, phpstan, pint, tests against MySQL / Postgres / SQLite / Redis. JIT is on.

```yaml
- uses: publicala/php-ci-static@v1
  with:
    php-version: '8.4'

- run: composer install --no-progress
- run: vendor/bin/pest
```

### Coverage with pcov (recommended)

10–100× faster than xdebug.

```yaml
- uses: publicala/php-ci-static@v1
  with:
    php-version: '8.4'
    coverage: pcov

- run: vendor/bin/pest --coverage
```

### Coverage with xdebug

```yaml
- uses: publicala/php-ci-static@v1
  with:
    php-version: '8.4'
    coverage: xdebug

- run: vendor/bin/pest --coverage
```

For step-debugging, override the mode inline:

```yaml
- run: php -d xdebug.mode=debug,coverage vendor/bin/pest --coverage
```

### Custom php.ini directives

```yaml
- uses: publicala/php-ci-static@v1
  with:
    php-version: '8.4'
    ini-values: memory_limit=512M, opcache.enable_cli=1

- run: vendor/bin/phpstan analyse
```

The action writes a `custom.ini` into its scan dir and exports `PHP_INI_SCAN_DIR`, so subsequent `php` calls pick the values up without `-d` flags. Use this for tuning that applies to the whole job; reach for `php -d key=value` for one-off overrides.

Values with commas can be passed either quoted (matches `shivammathur/setup-php`) or bare — the parser's smart split only treats a comma as a separator when it precedes `<directive>=`:

```yaml
ini-values: disable_functions="exec,passthru", memory_limit=512M
# equivalent to:
ini-values: disable_functions=exec,passthru, memory_limit=512M
```

For values that contain literal `key=value`-shaped substrings, quote them (or use YAML multiline `|`):

```yaml
ini-values: |
  memory_limit=512M
  error_log='/tmp/foo=bar.log'
```

## Sibling composite: `setup-php-vendor`

For fan-out CI topologies — one build job seeds `vendor/`, many consumer jobs (lint, phpstan, tests) read it back — `publicala/php-ci-static/setup-php-vendor@v1` bundles the PHP install with a Composer vendor restore in one step:

```yaml
# Seed (build) job — runs composer install, saves the cache under the
# composite's resolved key.
build:
  runs-on: depot-ubuntu-24.04
  steps:
    - uses: actions/checkout@v6
    - id: setup
      uses: publicala/php-ci-static/setup-php-vendor@v1
      with:
        php-version: '8.4'
        fail-on-cache-miss: 'false'   # seed job: a miss is expected
    - if: steps.setup.outputs.cache-hit != 'true'
      run: composer install --no-progress --prefer-dist --no-interaction
    - if: steps.setup.outputs.cache-hit != 'true'
      uses: actions/cache/save@v5
      with:
        path: vendor
        key: ${{ steps.setup.outputs.cache-key }}

# Consumer (fan-out) jobs — install PHP and restore vendor in one step.
test:
  needs: build
  runs-on: depot-ubuntu-24.04
  steps:
    - uses: actions/checkout@v6
    - uses: publicala/php-ci-static/setup-php-vendor@v1
      with:
        php-version: '8.4'
        coverage: pcov
        ini-values: memory_limit=512M
    - run: vendor/bin/pest --coverage
```

Inputs: `php-version`, `coverage`, `ini-values` (all forwarded to the root action), plus `dependency-path` (multi-line glob list, defaults to `composer.json` + `composer.lock`) and `fail-on-cache-miss` (default `'true'`; consumer-side a missing cache hard-fails so the operator is pointed at the seed job instead of seeing a vendor-less binary later).

Outputs: `cache-hit` (true on exact match) and `cache-key` (`composer-<runner.os>-php-<version>-<hash>`). Reuse `cache-key` verbatim in the seed job's `actions/cache/save@v5` step — that's the contract that keeps producer and consumer keys from drifting.

The composite is read-only by design. It does not run `composer install` and does not save the cache; both are decisions the caller's seed job owns, because install policy (skip-on-cache-hit, always-install, `--prefer-dist`, etc.) and save policy (always, only on miss) vary too much to fold into a default.

Scope: same as the root action — Linux x86_64, PHP 8.3/8.4/8.5. For monorepo / non-root composer setups, point `dependency-path` at the right files.

## Why

Third-party GH Actions runners (Depot, Blacksmith, Namespace, BuildJet) get flagged as self-hosted, so `shivammathur/setup-php` falls back to a PPA install (~85s on Depot vs ~6s on GH-hosted). A pre-built static binary skips that.

Context and benchmarks: [publicala/publicanow#7](https://github.com/publicala/publicanow/pull/7).

## Available releases

Sliding tags, refreshed on every successful build:

- `latest-8.3` → PHP 8.3 series
- `latest-8.4` → PHP 8.4 series
- `latest-8.5` → PHP 8.5 series

Each release publishes three assets plus a checksum file:

- `php-linux-x86_64` — static PHP CLI binary, all extensions baked in
- `pcov-linux-x86_64.so` — fast coverage driver, opt-in
- `xdebug-linux-x86_64.so` — xdebug Zend extension, opt-in
- `SHA256SUMS` — checksums for all three

pcov and xdebug are shared-only in static-php-cli, so they ship as separate `.so` files. Both are zero-cost when not loaded.

## Extensions

### Baked in (39, all static)

```
apcu        bcmath      calendar    ctype       curl
dom         exif        fileinfo    filter      gd
gmp         iconv       imagick     intl        mbstring
mysqli      opcache     openssl     pcntl       pdo
pdo_mysql   pdo_pgsql   pdo_sqlite  pgsql       phar
posix       redis       session     simplexml   soap
sockets     sodium      sqlite3     tokenizer   xml
xmlreader   xmlwriter   zip         zlib
```

`mbstring` ships with oniguruma support enabled, so `mb_split`,
`mb_ereg`, `mb_ereg_match`, and friends all work — Laravel's
`Illuminate\Support\Str` depends on this.

### Shared (downloaded separately)

```
pcov, xdebug
```

### What's intentionally not in here

- **node / npm / yarn** — use [`lorisleiva/laravel-docker`](https://github.com/lorisleiva/laravel-docker) when you need them in the same job.
- **mysql / postgres / redis client binaries** — same, use a container.
- **ghostscript, chromium** — system tools; out of scope for a static binary.

The pla-stack [runners reference](https://github.com/publicala/pla-stack/blob/main/references/github-actions-runners.md) documents the full three-tier strategy (static PHP → community container → custom container).

## Manual install (no GitHub Actions)

For Forge, raw shell, or any non-Actions runner. Same recipe the action runs internally:

```bash
BASE=https://github.com/publicala/php-ci-static/releases/download/latest-8.4
curl -fsSL -O "$BASE/php-linux-x86_64"
curl -fsSL -O "$BASE/SHA256SUMS"
grep ' php-linux-x86_64$' SHA256SUMS | sha256sum -c -
chmod +x php-linux-x86_64
sudo mv php-linux-x86_64 /usr/local/bin/php
php -v
```

Piping the matching line into `sha256sum -c` (rather than `sha256sum -c SHA256SUMS --ignore-missing`) guarantees the check actually ran — `--ignore-missing` would exit 0 even if nothing matched.

The binary ships with the upstream `php.ini-*` `memory_limit=128M` default, tuned for shared-hosting web SAPIs and well under what PHPCS / PHPStan / PHPUnit need on a real Laravel codebase. The composite action handles this transparently; for raw shell, pass `php -d memory_limit=-1 …` (or drop a `memory_limit=-1` ini into a directory and point `PHP_INI_SCAN_DIR` at it).

For coverage, download the `.so` and load it via `-d`:

```bash
curl -fsSL -o pcov.so "$BASE/pcov-linux-x86_64.so"
php -d extension=$PWD/pcov.so -d pcov.enabled=1 vendor/bin/pest --coverage
```

```bash
curl -fsSL -o xdebug.so "$BASE/xdebug-linux-x86_64.so"
php -d zend_extension=$PWD/xdebug.so -d xdebug.mode=coverage vendor/bin/pest --coverage
```

## Versioning

The composite action follows semver-style sliding tags:

- `@v1` — sliding, moves forward with backward-compatible releases. Pin this for stability.
- `@v1.0.0` — immutable; pin by exact tag if you want zero drift.
- `@main` — dev branch; use only for testing in-flight changes.

Breaking input changes will ship as `@v2`. See [CHANGELOG.md](CHANGELOG.md).

Releases are cut automatically by `.github/workflows/release.yml`: bumping the top `## vX.Y.Z` header in `CHANGELOG.md` and merging to `main` creates the immutable `vX.Y.Z` tag, force-moves the sliding `vX` tag, and publishes a GitHub Release whose body is the matching CHANGELOG block. The workflow is idempotent — re-running on a commit whose top version is already tagged is a no-op — and a PR check fails if the top header drifts from the `## vX.Y.Z` shape.

## Build

Matrix of 8.3 / 8.4 / 8.5 on `depot-ubuntu-24.04-16`, triggered by `workflow_dispatch`, a weekly cron, or any push to `main` that touches `.github/workflows/build.yml`. Each successful run overwrites the matching `latest-X.Y` release and moves the underlying git tag to the build commit.

## Scope

Linux x86_64 only. PHP 8.3, 8.4, 8.5. NTS (single-threaded). JIT enabled. Stripped binary.

All extensions are linked statically into the binary; only libc is dynamic (glibc). Every Ubuntu / Debian / Depot CI runner ships glibc, so the binary works out of the box. The dynamic libc is what allows `xdebug.so` and `pcov.so` to load via `zend_extension` — musl-static binaries cannot dlopen shared modules.
