# php-ci-static

Static PHP binaries for PLA CI. Built with [static-php-cli](https://github.com/crazywhalecc/static-php-cli), tuned to cover what Laravel apps actually need.

## Why

Third-party GH Actions runners (Depot, Blacksmith, Namespace, BuildJet) get flagged as self-hosted, so `shivammathur/setup-php` falls back to a PPA install (~85s on Depot vs ~6s on GH-hosted). A pre-built static binary skips that: one `curl`, one `chmod`, ready in a few seconds.

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

## Usage

### Default (no coverage, fastest)

The static binary covers the common Laravel CI workload — lint, phpstan, pint, tests against MySQL / Postgres / SQLite / Redis. JIT is on. No coverage driver loaded.

```yaml
- name: Install PHP
  run: |
    BASE=https://github.com/publicala/php-ci-static/releases/download/latest-8.4
    curl -fsSL -O "$BASE/php-linux-x86_64"
    curl -fsSL -O "$BASE/SHA256SUMS"
    sha256sum -c SHA256SUMS --ignore-missing
    chmod +x php-linux-x86_64
    sudo mv php-linux-x86_64 /usr/local/bin/php
    php -v
```

`sha256sum -c --ignore-missing` skips lines for files you didn't download (e.g., the `.so` modules below) but still verifies the binary you did. If the binary's hash doesn't match, the step fails.

### Coverage with pcov (recommended)

10–100× faster than xdebug. Download the shared module and load it via `extension` (pcov is a regular PHP extension, not a Zend extension like xdebug):

```yaml
- name: Install PHP + pcov
  run: |
    curl -fsSL -o php https://github.com/publicala/php-ci-static/releases/download/latest-8.4/php-linux-x86_64
    curl -fsSL -o pcov.so https://github.com/publicala/php-ci-static/releases/download/latest-8.4/pcov-linux-x86_64.so
    chmod +x php
    sudo mv php /usr/local/bin/php

- run: php -d extension=$PWD/pcov.so -d pcov.enabled=1 vendor/bin/pest --coverage
```

### Coverage with xdebug (or step-debugging)

```yaml
- name: Install PHP + xdebug
  run: |
    curl -fsSL -o php https://github.com/publicala/php-ci-static/releases/download/latest-8.4/php-linux-x86_64
    curl -fsSL -o xdebug.so https://github.com/publicala/php-ci-static/releases/download/latest-8.4/xdebug-linux-x86_64.so
    chmod +x php
    sudo mv php /usr/local/bin/php

- run: php -d zend_extension=$PWD/xdebug.so -d xdebug.mode=coverage vendor/bin/pest --coverage
```

## Extensions

### Baked in (38, all static)

```
apcu        bcmath      calendar    ctype       curl
dom         exif        fileinfo    filter      gd
gmp         iconv       intl        mbstring    mysqli
opcache     openssl     pcntl       pdo         pdo_mysql
pdo_pgsql   pdo_sqlite  pgsql       phar        posix
redis       session     simplexml   soap        sockets
sodium      sqlite3     tokenizer   xml         xmlreader
xmlwriter   zip         zlib
```

### Shared (downloaded separately)

```
pcov, xdebug
```

### What's intentionally not in here

- **node / npm / yarn** — use [`lorisleiva/laravel-docker`](https://github.com/lorisleiva/laravel-docker) when you need them in the same job.
- **mysql / postgres / redis client binaries** — same, use a container.
- **imagick, ghostscript, chromium** — system tools; out of scope for a static binary.

The pla-stack [runners reference](https://github.com/publicala/pla-stack/blob/main/references/github-actions-runners.md) documents the full three-tier strategy (static PHP → community container → custom container).

## Build

Manual trigger (`workflow_dispatch`). Matrix of 8.3 / 8.4 / 8.5 on `depot-ubuntu-24.04-16`. Each successful run overwrites the matching `latest-X.Y` release. Builds on non-`main` branches still produce workflow artifacts but skip the release publish step, so feature branches can verify the pipeline without touching production tags.

## Scope

Linux x86_64 only. PHP 8.3, 8.4, 8.5. NTS (single-threaded). JIT enabled. Stripped binary.

All extensions are linked statically into the binary; only libc is dynamic (glibc). Every Ubuntu / Debian / Depot CI runner ships glibc, so the binary works out of the box. The dynamic libc is what allows `xdebug.so` and `pcov.so` to load via `zend_extension` — musl-static binaries cannot dlopen shared modules.
