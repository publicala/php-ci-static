# php-ci-static

Static PHP binaries for PLA CI. Built with [static-php-cli](https://github.com/crazywhalecc/static-php-cli), scoped to what publicanow needs.

## Why

Third-party GH Actions runners (Depot, Blacksmith, Namespace, BuildJet) get flagged as self-hosted, so `shivammathur/setup-php` falls back to a PPA install (~85s on Depot vs ~6s on GH-hosted). A pre-built static binary skips that: one `curl`, one `chmod`, ready in a few seconds.

Context and benchmarks: [publicala/publicanow#7](https://github.com/publicala/publicanow/pull/7).

## Usage

From any GH Actions job:

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

Manual trigger (`workflow_dispatch`). Runs on `depot-ubuntu-24.04-16` and publishes a sliding release tag `latest-<major>.<minor>`. Each run overwrites the previous release asset.

## Scope (POC)

Linux x86_64, PHP 8.4. Extensions tuned for publicanow (Laravel 12, Pest 4, SQLite, Horizon, DomPDF):

```
bcmath, ctype, curl, dom, fileinfo, filter, gd, iconv, intl, mbstring, opcache, openssl,
pcntl, pdo, pdo_sqlite, phar, posix, session, simplexml, sockets, sqlite3, tokenizer,
xml, xmlreader, xmlwriter, zip, zlib
```

No pcov (unused). No xdebug. No MySQL driver yet (tests run on SQLite).
