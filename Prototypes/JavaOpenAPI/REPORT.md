# Java-derived OpenAPI prototype

Files: gen_openapi.rb, generate.sh, openapi.json, openapi-generator-config.yaml, gen-report.json,
Sources/JavaProtoTypes/Types.swift (generated, swift-openapi-generator 1.11.0), Sources/DecodeCheck/main.swift,
reports/{new,old}-{live,fixtures,docs*}.json, scan_mismatch.rb, prepare_inputs.rb, all/ (all 334 methods: openapi.json, generated Types.swift, compiled OK in all/pkg).

## How to run
From `Prototypes/JavaOpenAPI`; needs `bundle install`, `git submodule update --init` and `swift build --package-path ../../Tools` at the repo root first.
The Java sources are parsed with tree-sitter (`ruby_tree_sitter` gem + the `vendor/tree-sitter-java` grammar, a git submodule pinned to one commit), so the grammar must be compiled once with `make tree-sitter-java` at the repo root (output in `.tmp/tree-sitter-java/`; `generate.sh` runs it for you, and `gen_openapi.rb` accepts `TREE_SITTER_JAVA_LIB=<path>` to use another build).
```sh
sh generate.sh                                          # Java sources -> openapi.json -> Sources/JavaProtoTypes/Types.swift
LIVE_RESPONSES=/path/to/responses BUNDLE_GEMFILE=../../Gemfile bundle exec ruby prepare_inputs.rb  # optional env; fills inputs/ (git-ignored)
swift build
for k in live fixtures docs; do .build/debug/DecodeCheck inputs/$k reports/new-$k.json; done
(cd OldHarness && swift build && for k in live fixtures docs1 docs2; do .build/debug/Harness ../inputs/$([ $k = live ] && echo live || echo old-$k) ../reports/old-$k.json; done)
BUNDLE_GEMFILE=../../Gemfile bundle exec ruby scan_mismatch.rb   # static JSON-vs-schema check against all/openapi.json
```
`gen_openapi.rb` walks the tree-sitter syntax tree of each model/response class (fields, `@SerializedName`, types, nesting, imports) instead of tokenizing Java by hand; it raises with file:line on syntax errors or Java constructs it does not model.
(Run the Ruby scripts as `BUNDLE_GEMFILE=../../Gemfile bundle exec ruby <script>`; `generate.sh` sets this itself.)

## Decode (new = Java-derived; old = swift-slack today). dropped = payload paths lost in decode->encode (leaf-most)
| method | live new/old | fixture new/old | docs new/old |
|---|---|---|---|
| team.info | ok 0 / ok 8 | ok 0 / ok 15 | ok 0 / ok 5 |
| users.info | ok 0 / ok 0 | ok 0 / ok 9 | ok 0 / ok 0 |
| conversations.list | ok 1 (parent_conversation:null) / ok 4 | ok 1 (callstack) / ok 6 | ok 0 (both examples) / ok 3, 2 |
| chat.postMessage | ok 0 / ok 2 | FAIL message.blocks[0].elements[0].url "Invalid URL string" / FAIL (same, attachments[].blocks) | ok 0 / ok 0 |
| admin.conversations.getConversationPrefs | no live | ok 0 / ok 6 | ex1 FAIL prefs.who_can_post.type (string where Java has List<String>) / ok 2 ; ex2 ok 0 / ok 4 |
