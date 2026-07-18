#!/usr/bin/env sh

set -xe

TMP_DIR="./.tmp"
DEPS_DIR="./vendor"

ruby -e 'version = RUBY_VERSION.split(".").first(2).map(&:to_i); abort "Ruby 3.0+ is required (active: #{RUBY_VERSION}). Activate the version from .ruby-version." if (version <=> [3, 0]) == -1'

if [ ! -x "./node_modules/.bin/quicktype" ]; then
    echo "Error: Locked quicktype dependency is not installed. Run 'npm ci' first."
    exit 1
fi

# Ensure submodules are initialized and updated
if [ ! -f ".gitmodules" ]; then
    echo "Error: .gitmodules file not found. Please run 'make update' first."
    exit 1
fi

# Check if submodules are initialized (note: .git can be a file or directory)
if [ ! -e "${DEPS_DIR}/java-slack-sdk/.git" ] || [ ! -e "${DEPS_DIR}/slack-api-ref/.git" ]; then
    echo "Error: Submodules not initialized. Please run 'make update' first."
    exit 1
fi

rm -rf "${TMP_DIR}/WebAPI" \
    "${TMP_DIR}/Events" \
    "Sources/SlackClient/WebAPI/Generated" \
    "Sources/SlackApp/Events/Generated" \
    "Sources/SlackModels/Generated"

mkdir -p "${TMP_DIR}/WebAPI"
mkdir -p "${TMP_DIR}/Events"

ruby scripts/generate_webapi.rb

# Generate types with public and client with internal to avoid potential conflict other symbols named `Client`
swift run --disable-sandbox swift-openapi-generator generate \
    --mode types \
    --access-modifier public \
    --naming-strategy idiomatic \
    --output-directory "${TMP_DIR}/WebAPI" \
    "${TMP_DIR}/WebAPI/openapi.json"

swift run --disable-sandbox swift-openapi-generator generate \
    --mode client \
    --access-modifier internal \
    --naming-strategy idiomatic \
    --output-directory "${TMP_DIR}/WebAPI" \
    "${TMP_DIR}/WebAPI/openapi.json"

ruby scripts/process_webapi.rb "${TMP_DIR}/WebAPI" "Sources/SlackClient/WebAPI/Generated"

# Generate events
ruby scripts/generate_events.rb

swift run --disable-sandbox swift-openapi-generator generate \
    --mode types \
    --access-modifier public \
    --naming-strategy idiomatic \
    --output-directory "${TMP_DIR}/Events" \
    "${TMP_DIR}/Events/openapi.json"

ruby scripts/process_events.rb "${TMP_DIR}/Events/Types.swift" "Sources/SlackApp/Events/Generated"

make format
