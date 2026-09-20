#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/freespeak-store-tests.XXXXXX")"
trap 'rm -rf "$test_build_dir"' EXIT

xcrun swiftc -swift-version 6 -parse-as-library -default-isolation MainActor \
  "$repo_root/FreeSpeak/Models/AppModels.swift" \
  "$repo_root/FreeSpeak/Models/AppStore.swift" \
  "$repo_root/Tests/AppStoreTestDoubles.swift" \
  "$repo_root/Tests/AppStoreLifecycleTests.swift" \
  -o "$test_build_dir/store-tests"
"$test_build_dir/store-tests"
