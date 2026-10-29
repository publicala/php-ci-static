#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/build-plan.bash
source "$root/scripts/build-plan.bash"

fail() {
  echo "::error::$1"
  exit 1
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  [[ "$actual" == "$expected" ]] || fail "$message (expected '$expected', got '$actual')"
}

assert_fails() {
  local message="$1"
  shift

  if "$@" >/dev/null 2>&1; then
    fail "$message"
  fi
}

# Answers like php.net's releases API: the newest patch per series,
# and an error object for a series it does not know.
curl() {
  case "${*: -1}" in
    *version=8.3) echo '{"version":"8.3.36","date":"21 Oct 2026"}' ;;
    *version=8.4) echo '{"version":"8.4.27","date":"21 Oct 2026"}' ;;
    *version=8.5) echo '{"version":"8.5.12","date":"21 Oct 2026"}' ;;
    *version=8.6) echo '{"version":"8.60.1"}' ;;
    *) echo '{"error":"Unknown version"}' ;;
  esac
}

# Only php-8.3.36 is published, and php-8.5.12 is a leftover draft.
gh() {
  case "$3" in
    php-8.3.36) echo 'false' ;;
    php-8.5.12) echo 'true' ;;
    *)
      echo 'release not found' >&2
      return 1
      ;;
  esac
}

test_latest_patch_reads_php_net() {
  assert_equals '8.4.27' "$(php_ci_static_latest_patch 8.4)" \
    "the newest patch should come from php.net"
}

test_latest_patch_rejects_unknown_series() {
  assert_fails "an unknown series should fail" php_ci_static_latest_patch 7.9
}

test_latest_patch_rejects_patch_from_another_series() {
  assert_fails "8.60.1 must not pass as a patch of 8.6" php_ci_static_latest_patch 8.6
}

test_latest_patch_fails_when_php_net_is_unreachable() {
  (
    # shellcheck disable=SC2329 # invoked by php_ci_static_latest_patch
    curl() {
      return 22
    }
    assert_fails "an unreachable php.net should fail" php_ci_static_latest_patch 8.4
  )
}

test_scheduled_matrix_builds_only_unpublished_patches() {
  assert_equals '[{"series":"8.4","version":"8.4.27"},{"series":"8.5","version":"8.5.12"}]' \
    "$(php_ci_static_build_matrix schedule 8.3 8.4 8.5 2>/dev/null)" \
    "a scheduled run should skip published patches and rebuild drafts"
}

test_scheduled_matrix_is_empty_when_everything_is_published() {
  assert_equals '[]' "$(php_ci_static_build_matrix schedule 8.3 2>/dev/null)" \
    "a scheduled run with nothing new should build nothing"
}

test_manual_matrix_builds_every_series() {
  assert_equals '[{"series":"8.3","version":"8.3.36"},{"series":"8.4","version":"8.4.27"},{"series":"8.5","version":"8.5.12"}]' \
    "$(php_ci_static_build_matrix workflow_dispatch 8.3 8.4 8.5)" \
    "a manual run should build every series at its newest patch"
}

test_matrix_fails_when_any_series_cannot_be_resolved() {
  assert_fails "an unresolvable series should fail the whole matrix" \
    php_ci_static_build_matrix workflow_dispatch 8.4 7.9
}

test_latest_patch_reads_php_net
test_latest_patch_rejects_unknown_series
test_latest_patch_rejects_patch_from_another_series
test_latest_patch_fails_when_php_net_is_unreachable
test_scheduled_matrix_builds_only_unpublished_patches
test_scheduled_matrix_is_empty_when_everything_is_published
test_manual_matrix_builds_every_series
test_matrix_fails_when_any_series_cannot_be_resolved

echo "build plan tests passed"
