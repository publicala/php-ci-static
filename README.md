# php-ci-static

PHP runtime setup for PLA CI. The default installs a pre-built static PHP CLI from a verified Publica.la release. Controlled fallbacks validate PHP from an official container or install PHP from Homebrew on a native macOS job. Consumers use one internal `uses:` step in all three cases.

## Quick start

```yaml
- uses: publicala/php-ci-static@v1
  with:
    php-version: '8.4'
    coverage: pcov           # optional, default: none
```

That's it. The action resolves the current `8.4` binary release, restores the verified runtime assets from GitHub's cache when available, puts both `php` and `composer` on `PATH`, and (if `coverage` is set) auto-loads the coverage driver via `PHP_INI_SCAN_DIR` so subsequent `php` calls see it automatically.

## Runtime sources

`runtime: static` is the default. It supports PHP 8.3, 8.4, and 8.5 on Linux x86_64. Use it for normal CI jobs.

`runtime: system` validates a PHP runtime that is already on `PATH` and installs Composer. Its main use is an official PHP container for compatibility checks that need an older PHP series:

```yaml
jobs:
  php-compatibility:
    runs-on: ubuntu-24.04
    container: php:7.4-cli
    steps:
      - uses: actions/checkout@v7
      - uses: publicala/php-ci-static@v1
        with:
          php-version: '7.4'
          runtime: system
```

`runtime: homebrew` installs the requested Homebrew PHP formula and Composer on a native macOS job. Use it when the job must produce or test a macOS artifact:

```yaml
jobs:
  macos-build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v7
      - uses: publicala/php-ci-static@v1
        with:
          php-version: '8.5'
          runtime: homebrew
```

The `system` and `homebrew` sources support `coverage: none` and no custom `ini-values`. The static source remains the only source that manages coverage modules and PHP configuration.

## Development

```bash
npm install
npm test
npm run hooks:install
```

`npm test` runs the local tooling harness used in CI: Prettier for repo tooling files, `github-actionlint` for workflow files, and ShellCheck for embedded Bash in workflows and composite actions.

## Inputs

| Input | Required | Default | Accepted values |
| --- | --- | --- | --- |
| `php-version` | yes | n/a | Static: `8.3`, `8.4`, `8.5`. System: `7.4`, `8.1` through `8.5`. Homebrew: `8.1` through `8.5` |
| `runtime` | no | `static` | `static`, `system`, `homebrew` |
| `coverage` | no | `none` | `none`, `pcov`, `xdebug` |
| `ini-values` | no | `''` | Comma-separated `key=value` pairs |

When `coverage: xdebug`, the action sets `xdebug.mode=coverage` (mirroring `shivammathur/setup-php`). Override inline with `php -d xdebug.mode=...` for step-debugging or other modes.

The action also drops a baseline `memory_limit=-1` into the scan dir on every run, so CI workloads (PHPCS, PHPStan, PHPUnit on Laravel-sized codebases) don't hit the static binary's compiled-in 128M default. Override with `ini-values: memory_limit=512M` (or any other value) if you want a cap.

`ini-values` accepts php.ini directives, comma- or newline-separated. e.g. `memory_limit=512M, opcache.enable_cli=1`. Two ways to handle commas inside values: wrap the value in single or double quotes (`disable_functions="exec,passthru"`, matching `shivammathur/setup-php`), or rely on the smart-split fallback that treats a comma as a separator only when it precedes a `<directive>=` (so unquoted `disable_functions=exec,passthru` also works). Quote when the value contains `key=value`-shaped substrings (`error_log='/tmp/foo=bar.log'`). Composes with `coverage:` (both write into the same scan dir and load together).

Composer (stable) is always installed alongside `php`. It's a ~2-3s download and every realistic CI job needs it, so there's no opt-out.

The PHP binary and coverage modules are cached by concrete release tag and `SHA256SUMS` hash. The cache lives in the consuming repository's Actions cache, so one seed job can populate it for the fan-out jobs that follow. Cache misses download release assets with retries, verify them against a fresh checksum file, and save immediately after verification. Composer is not cached here because `composer-stable.phar` is a rolling download.

Output: `runtime-cache-hit` is the string `true` when the PHP runtime cache restored an exact match. Most consumers do not need it, but it is useful for CI diagnostics.

## Examples

### Default (no coverage, fastest)

The static binary covers the common Laravel CI workload: lint, phpstan, pint, tests against MySQL / Postgres / SQLite / Redis. JIT is on.

On a cold runtime cache, the action downloads the PHP binary plus both coverage modules so the same verified cache can serve later `pcov` and `xdebug` jobs. On a hit, `coverage: none` still avoids loading coverage extensions.

```yaml
- uses: publicala/php-ci-static@v1
  with:
    php-version: '8.4'

- run: composer install --no-progress
- run: vendor/bin/pest
```

### Coverage with pcov (recommended)

10-100× faster than xdebug.

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

The action writes a `custom.ini` into its scan dir and exports `PHP_INI_SCAN_DIR`, so subsequent `php` calls pick the values up without `-d` flags. Use this for tuning that applies to the whole job. Reach for `php -d key=value` for one-off overrides.

Values with commas can be passed either quoted (matches `shivammathur/setup-php`) or bare. The parser's smart split only treats a comma as a separator when it precedes `<directive>=`:

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

For fan-out CI topologies, where one build job seeds `vendor/` and many consumer jobs (lint, phpstan, tests) read it back, `publicala/php-ci-static/setup-php-vendor@v1` bundles the PHP install with a Composer vendor restore in one step:

```yaml
# Seed (build) job. Runs composer install, saves the cache under the
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

# Consumer (fan-out) jobs install PHP and restore vendor in one step.
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

Inputs: `php-version`, `coverage`, `ini-values` (all forwarded to the root action), plus `dependency-path` (multi-line glob list, defaults to `composer.json` + `composer.lock`) and `fail-on-cache-miss` (default `'true'`, consumer-side a missing cache hard-fails so the operator is pointed at the seed job instead of seeing a vendor-less binary later).

Outputs: `cache-hit` (true on exact match) and `cache-key` (`composer-<runner.os>-php-<version>-<hash>`). Reuse `cache-key` verbatim in the seed job's `actions/cache/save@v5` step. That's the contract that keeps producer and consumer keys from drifting.

The composite is read-only by design. It does not run `composer install` and does not save the cache. Both are decisions the caller's seed job owns, because install policy (skip-on-cache-hit, always-install, `--prefer-dist`, etc.) and save policy (always, only on miss) vary too much to fold into a default.

Scope: same as the root action's static source. Linux x86_64 with PHP 8.3, 8.4, or 8.5. For monorepo or non-root Composer setups, point `dependency-path` at the right files.

## Why

Third-party GH Actions runners (Depot, Blacksmith, Namespace, BuildJet) get flagged as self-hosted, so `shivammathur/setup-php` falls back to a PPA install + apt dependency fetch + extension compile instead of the pre-built tarball it downloads on GH-hosted runners. A pre-built static binary skips that fallback entirely.

Install step, measured on Depot (`depot-ubuntu-24.04`), N=3 runs, variance ≤5s:

| Strategy                                      | Install step                 |
| --------------------------------------------- | ---------------------------- |
| GH-hosted `ubuntu-24.04` + `setup-php`        | ~6s (baseline)               |
| Depot `depot-ubuntu-24.04` + `setup-php`      | ~83s                         |
| Depot + `lorisleiva/laravel-docker` container | ~9s (+ ~35s cold image pull) |
| Depot + `php.new` static                      | ~5s (8.5-only at the time)   |
| **Depot + `publicala/php-ci-static`**         | **<1s**                      |

The slow path triggers whenever a runner reports `RUNNER_ENVIRONMENT=self-hosted`, which every third-party provider does even though their images mirror GitHub's own. Prior art, with the maintainer's rationale for not special-casing these runners: [`shivammathur/setup-php#1056`](https://github.com/shivammathur/setup-php/issues/1056).

## Available releases

Every build publishes one immutable release per PHP patch, tagged `php-<version>` (for example `php-8.4.21`). A mutable pointer on the `channels` branch records the newest release for each series, and the action reads it to resolve the right binary:

- `channels/8.3` points at the newest `php-8.3.*` release
- `channels/8.4` points at the newest `php-8.4.*` release
- `channels/8.5` points at the newest `php-8.5.*` release

The organization enforces immutable releases, so binaries can no longer be overwritten in place. Publishing each patch as its own immutable release (and sliding a tiny text pointer instead of the assets) keeps "latest" working while every published binary stays tamper-proof and verifiable. The pre-immutability `latest-8.x` releases are frozen. The action falls back to them only if the pointer is unreachable.

Each release publishes raw assets, zstd-compressed copies, and a checksum file:

- `php-linux-x86_64`: static PHP CLI binary, all extensions baked in
- `pcov-linux-x86_64.so`: fast coverage driver, opt-in
- `xdebug-linux-x86_64.so`: xdebug Zend extension, opt-in
- `*.zst`: compressed copies of the three assets above, used automatically when `zstd` is available
- `SHA256SUMS`: checksums for raw and compressed assets

pcov and xdebug are shared-only in static-php-cli, so they ship as separate `.so` files. Both are zero-cost when not loaded.

Older immutable `php-*` releases may be raw-only. The action checks `SHA256SUMS` before choosing the download path, so those releases keep working through the raw fallback.

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

`mbstring` ships with oniguruma support enabled, so `mb_split`, `mb_ereg`, `mb_ereg_match`, and friends all work. Laravel's `Illuminate\Support\Str` depends on this.

### Shared (downloaded separately)

```
pcov, xdebug
```

### What's intentionally not in here

- **node / npm / yarn**: use [`lorisleiva/laravel-docker`](https://github.com/lorisleiva/laravel-docker) when you need them in the same job.
- **mysql / postgres / redis client binaries**: same, use a container.
- **ghostscript, chromium**: system tools, out of scope for a static binary.

Three-tier strategy: static PHP for the common Laravel CI workload, [`lorisleiva/laravel-docker`](https://github.com/lorisleiva/laravel-docker) when a job needs a fuller toolchain (node, client binaries), and a custom container when it needs everything. Each job picks the lightest tier that covers it.

## Manual install (no GitHub Actions)

For Forge, dev containers, raw shell, or any non-Actions runner, `scripts/install-php.bash` runs the same resolve-verify-install recipe the action runs internally: it resolves the current release for your series from the `channels` pointer, downloads and checksum-verifies the binary, installs it onto `PATH`, and renders optional ini directives into the binary's compiled-in scan dir (`/usr/local/etc/php/conf.d`), so they apply to every later `php` call without `PHP_INI_SCAN_DIR`.

```bash
base=https://raw.githubusercontent.com/publicala/php-ci-static/v1/scripts
curl -fsSL -O "$base/runtime-assets.bash"
curl -fsSL -O "$base/install-php.bash"
bash install-php.bash --php-version 8.4 --ini-values 'memory_limit=512M, opcache.enable_cli=1'
php -v
```

The script sources its sibling `runtime-assets.bash`, so fetch both files from the same ref (or run it from a checkout). `--bin-dir` (default `/usr/local/bin`) and `--conf-dir` (default `/usr/local/etc/php/conf.d`) relocate the install; writing to the defaults needs root. `ini-values` accepts the same syntax as the action input.

The binary ships with the upstream `php.ini-*` `memory_limit=128M` default, tuned for shared-hosting web SAPIs and well under what PHPCS / PHPStan / PHPUnit need on a real Laravel codebase. Like the action, the script drops a baseline `memory_limit=-1` into the scan dir on every run; the file rendered from `--ini-values` sorts later, so your values win.

To pin an exact patch instead of following the pointer, download from a specific release yourself, e.g. `https://github.com/publicala/php-ci-static/releases/download/php-8.4.21`, verifying against its `SHA256SUMS` (pipe the matching line into `sha256sum -c -`; `--ignore-missing` would exit 0 even if nothing matched).

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

- `@v1`: sliding, moves forward with backward-compatible releases. Pin this for stability.
- `@v1.0.0`: immutable, pin by exact tag if you want zero drift.
- `@main`: dev branch, use only for testing in-flight changes.

Breaking input changes will ship as `@v2`. See [CHANGELOG.md](CHANGELOG.md).

Releases are cut automatically by `.github/workflows/release.yml`: bumping the top `## vX.Y.Z` header in `CHANGELOG.md` and merging to `main` creates the immutable `vX.Y.Z` tag, force-moves the sliding `vX` tag, and publishes a GitHub Release whose body is the matching CHANGELOG block. The workflow is idempotent (re-running on a commit whose top version is already tagged is a no-op), and a PR check fails if the top header drifts from the `## vX.Y.Z` shape.

## Build

Matrix of 8.3 / 8.4 / 8.5 on `depot-ubuntu-24.04-16`, triggered by `workflow_dispatch`, a weekly cron, or any push to `main` that touches `.github/workflows/build.yml`. Each successful run publishes an immutable `php-<version>` release (a no-op if that patch is already published) and repoints `channels/<series>` at it.

## Scope

The default static source supports Linux x86_64 with PHP 8.3, 8.4, or 8.5. It uses NTS, enables JIT, and strips the binary. The system source supports PHP 7.4 or 8.1 through 8.5 when the exact requested series is already on `PATH`. The Homebrew source supports PHP 8.1 through 8.5 on macOS.

All extensions are linked statically into the binary. Only libc is dynamic (glibc). Every Ubuntu / Debian / Depot CI runner ships glibc, so the binary works out of the box. The dynamic libc is what allows `xdebug.so` and `pcov.so` to load via `zend_extension`. musl-static binaries cannot dlopen shared modules.
