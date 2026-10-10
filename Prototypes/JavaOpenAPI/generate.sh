#!/bin/sh
# Regenerate openapi.json from the java-slack-sdk Java sources, then run swift-openapi-generator
# (the version pinned in the repo's Tools package) over it.
#
# Prerequisites (from the repo root): `bundle install`, `git submodule update --init` and `swift build --package-path Tools`.
# The tree-sitter Java grammar (vendor/tree-sitter-java) is compiled on demand by `make tree-sitter-java`.
set -e
cd "$(dirname "$0")"
ROOT=../..
export BUNDLE_GEMFILE="$ROOT/Gemfile"
export SLACKBLOCKKIT_DIR="$ROOT/Sources/SlackBlockKit"

make -s -C "$ROOT" tree-sitter-java

bundle exec ruby gen_openapi.rb "$ROOT/vendor/java-slack-sdk" openapi.json openapi-generator-config.yaml \
  team.info users.info conversations.list chat.postMessage admin.conversations.getConversationPrefs

rm -f Sources/JavaProtoTypes/Types.swift
"$ROOT/Tools/.build/debug/swift-openapi-generator" generate --config openapi-generator-config.yaml \
  --output-directory Sources/JavaProtoTypes openapi.json
