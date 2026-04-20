# php-ci-static

Static PHP binaries for PLA CI. Built with [static-php-cli](https://github.com/crazywhalecc/static-php-cli), scoped to what publicanow needs.

## Why

Third-party GH Actions runners (Depot, Blacksmith, Namespace, BuildJet) get flagged as self-hosted, so `shivammathur/setup-php` falls back to a PPA install (~85s on Depot vs ~6s on GH-hosted). A pre-built static binary skips that: one `curl`, one `chmod`, ready in a few seconds.

Context and benchmarks: [publicala/publicanow#7](https://github.com/publicala/publicanow/pull/7).

## Available releases

Sliding tags, updated on every successful build:

- `latest-8.3` → PHP 8.3 series
- `latest-8.4` → PHP 8.4 series
- `latest-8.5` → PHP 8.5 series

## Usage

From any GH Actions job (swap `8.4` for your series):

```yaml
- name: Install PHP
  run: |
    curl -fsSL -o php https://github.com/publicala/php-ci-static/releases/download/latest-8.4/php-linux-x86_64
    chmod +x php
    sudo mv php /usr/local/bin/php
    php -v
```

Checksum (optional):

```yaml
    curl -fsSL -O https://github.com/publicala/php-ci-static/releases/download/latest-8.4/SHA256SUMS
    sha256sum -c SHA256SUMS --ignore-missing
```

## Build

Manual trigger (`workflow_dispatch`). Runs a matrix of 8.3 / 8.4 / 8.5 on `depot-ubuntu-24.04-16` and publishes sliding tags `latest-<major>.<minor>`. Each run overwrites previous release assets.

## Scope (POC)

Linux x86_64, PHP 8.3 + 8.4 + 8.5. Extensions tuned for publicanow (Laravel 12, Pest 4, SQLite, Horizon, DomPDF) and shared across all versions:

```
bcmath, ctype, curl, dom, fileinfo, filter, gd, iconv, intl, mbstring, opcache, openssl,
pcntl, pdo, pdo_sqlite, phar, posix, session, simplexml, sockets, sqlite3, tokenizer,
xml, xmlreader, xmlwriter, zip, zlib
```

No pcov (unused). No xdebug. No MySQL driver yet (tests run on SQLite).
