#!/usr/bin/env bash
# tests/helpers.bash — shared fixtures for the VIGIL bats suite.
#
# Every test sources this file via `load helpers`.
# Bash 3.2 compatible: no associative arrays, no ${var,,}, no readarray/mapfile.

# Absolute path to the VIGIL repo root (one level up from this file).
VIGIL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export VIGIL_ROOT

setup() {
  # Each test runs in its own pristine project dir.
  TEST_PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT"
  cd "$TEST_PROJECT"
}

teardown() {
  cd "$VIGIL_ROOT"
}
