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

## Inputs

| Input | Required | Default | Accepted values |
|-------|----------|---------|-----------------|
| `php-version` | yes | — | `8.3`, `8.4`, `8.5` |
| `coverage` | no | `none` | `none`, `pcov`, `xdebug` |
| `ini-values` | no | `''` | Comma-separated `key=value` pairs |

When `coverage: xdebug`, the action sets `xdebug.mode=coverage` (mirroring `shivammathur/setup-php`). Override inline with `php -d xdebug.mode=...` for step-debugging or other modes.

`ini-values` accepts php.ini directives, comma- or newline-separated — e.g. `memory_limit=512M, opcache.enable_cli=1`. Commas inside values are preserved (only commas that precede a `<directive>=` separate entries), so `disable_functions=exec,passthru` works. For values that contain `key=value`-shaped substrings, use YAML multiline. Composes with `coverage:`; both write into the same scan dir and load together.

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

For values that contain commas (`disable_functions=exec,passthru`) the inline form still works — the parser only treats a comma as a separator when it precedes `<directive>=`. For values that contain `key=value`-shaped substrings, use YAML multiline:

```yaml
- uses: publicala/php-ci-static@v1
  with:
    php-version: '8.4'
    ini-values: |
      memory_limit=512M
      disable_functions=exec,passthru
```

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

## Build

Matrix of 8.3 / 8.4 / 8.5 on `depot-ubuntu-24.04-16`, triggered by `workflow_dispatch`, a weekly cron, or any push to `main` that touches `.github/workflows/build.yml`. Each successful run overwrites the matching `latest-X.Y` release and moves the underlying git tag to the build commit.

## Scope

Linux x86_64 only. PHP 8.3, 8.4, 8.5. NTS (single-threaded). JIT enabled. Stripped binary.

All extensions are linked statically into the binary; only libc is dynamic (glibc). Every Ubuntu / Debian / Depot CI runner ships glibc, so the binary works out of the box. The dynamic libc is what allows `xdebug.so` and `pcov.so` to load via `zend_extension` — musl-static binaries cannot dlopen shared modules.
