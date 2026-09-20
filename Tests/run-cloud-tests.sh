#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/freespeak-cloud-tests.XXXXXX")"
trap 'rm -rf "$test_build_dir"' EXIT

xcrun swiftc -swift-version 6 -parse-as-library \
  "$repo_root/FreeSpeak/Models/AppModels.swift" \
  "$repo_root/FreeSpeak/Services/CloudSpeechService.swift" \
  "$repo_root/Tests/CloudSpeechServiceTests.swift" \
  -o "$test_build_dir/cloud-tests"
"$test_build_dir/cloud-tests"
