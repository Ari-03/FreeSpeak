#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/steno-audio-tests.XXXXXX")"
trap 'rm -rf "$test_build_dir"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -default-isolation MainActor \
  "$repo_root/FreeSpeak/Services/AudioOperation.swift" \
  "$repo_root/Tests/AudioOperationTests.swift" \
  -o "$test_build_dir/audio-tests"
"$test_build_dir/audio-tests"
