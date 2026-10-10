#!/usr/bin/env sh

# Regenerates the Web API client, response models and events:
#   scripts/generate_webapi.rb  slack-api-ref methods + java-slack-sdk classes -> .tmp/WebAPI/openapi.json
#   swift-openapi-generator     openapi.json -> .tmp/WebAPI/{Types,Client}.swift
#   scripts/process_webapi.rb   -> Sources/SlackClient/WebAPI/Generated, Sources/SlackApp/Events/Generated

set -xe

TMP_DIR="./.tmp/WebAPI"
DEPS_DIR="./vendor"

ruby -e 'version = RUBY_VERSION.split(".").first(2).map(&:to_i); abort "Ruby 3.0+ is required (active: #{RUBY_VERSION}). Activate the version from .ruby-version." if (version <=> [3, 0]) == -1'

if [ ! -e "${DEPS_DIR}/java-slack-sdk/.git" ] || [ ! -e "${DEPS_DIR}/slack-api-ref/.git" ] || [ ! -e "${DEPS_DIR}/tree-sitter-java/.git" ]; then
    echo "Error: Submodules not initialized. Run 'git submodule update --init'."
    exit 1
fi

make tree-sitter-java

rm -rf "${TMP_DIR}" \
    "Sources/SlackClient/WebAPI/Generated" \
    "Sources/SlackApp/Events/Generated"
mkdir -p "${TMP_DIR}/Swift"

bundle exec ruby scripts/generate_webapi.rb

# Types are public; the client is internal to avoid conflicts with other symbols named `Client`.
swift run --package-path Tools --disable-sandbox swift-openapi-generator generate \
    --config "${TMP_DIR}/types-config.yaml" \
    --output-directory "${TMP_DIR}/Swift" \
    "${TMP_DIR}/openapi.json"

swift run --package-path Tools --disable-sandbox swift-openapi-generator generate \
    --config "${TMP_DIR}/client-config.yaml" \
    --output-directory "${TMP_DIR}/Swift" \
    "${TMP_DIR}/openapi.json"

bundle exec ruby scripts/process_webapi.rb "${TMP_DIR}/Swift" "${TMP_DIR}/openapi.json"

make format-generated
