# channels branch (release pointers)

This orphan branch holds the mutable "latest" pointers for php-ci-static's
binary releases. It is data, not code. Do not merge it into `main`.

Each file is named for a PHP series and contains the base download URL of the
newest immutable release for that series:

    8.3  ->  https://github.com/publicala/php-ci-static/releases/download/php-8.3.x
    8.4  ->  https://github.com/publicala/php-ci-static/releases/download/php-8.4.x
    8.5  ->  https://github.com/publicala/php-ci-static/releases/download/php-8.5.x

## Why this exists

The organization enforces immutable GitHub Releases, so the old sliding
`latest-8.x` releases can no longer be overwritten. Each build now publishes
one immutable release per PHP patch (for example `php-8.4.21`) and updates the
pointer here.

The build writes these files through the GitHub Contents API. The composite
action reads them through `raw.githubusercontent.com`, then verifies the
downloaded binary against the release's `SHA256SUMS`.

Pointers are seeded at the frozen `latest-8.x` releases. The first immutable
per-version build repoints each one at its `php-X.Y.Z` release.
