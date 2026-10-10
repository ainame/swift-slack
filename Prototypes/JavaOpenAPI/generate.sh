#!/bin/sh
# Regenerate openapi.json from the java-slack-sdk Java sources, then run swift-openapi-generator
# (the version pinned in the repo's Tools package) over it.
#
# Prerequisites (from the repo root): `bundle install` and `swift build --package-path Tools`.
set -e
cd "$(dirname "$0")"
ROOT=../..
export BUNDLE_GEMFILE="$ROOT/Gemfile"
export SLACKBLOCKKIT_DIR="$ROOT/Sources/SlackBlockKit"

bundle exec ruby gen_openapi.rb "$ROOT/vendor/java-slack-sdk" openapi.json openapi-generator-config.yaml \
  team.info users.info conversations.list chat.postMessage admin.conversations.getConversationPrefs

rm -f Sources/JavaProtoTypes/Types.swift
"$ROOT/Tools/.build/debug/swift-openapi-generator" generate --config openapi-generator-config.yaml \
  --output-directory Sources/JavaProtoTypes openapi.json
