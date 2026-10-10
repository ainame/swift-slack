# Java-derived OpenAPI prototype

Files: gen_openapi.rb, type_overrides.yml, generate.sh, openapi.json, openapi-generator-config.yaml, gen-report.json,
Sources/JavaProtoTypes/Types.swift (generated, swift-openapi-generator 1.11.0), Sources/DecodeCheck/main.swift,
reports/{new,old}-{live,fixtures,docs*}.json, scan_mismatch.rb, prepare_inputs.rb, java_placeholders.rb, decode_all.rb, all/ (all 334 methods: openapi.json, generated Types.swift, compiled OK in all/pkg).

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
BUNDLE_GEMFILE=../../Gemfile bundle exec ruby decode_all.rb      # all 334 fixtures: regenerate all/, build all/pkg, decode, group failures (--raw: without placeholder stripping)
```
`gen_openapi.rb` walks the tree-sitter syntax tree of each model/response class (fields, `@SerializedName`, types, nesting, imports) instead of tokenizing Java by hand; it raises with file:line on syntax errors or Java constructs it does not model.
(Run the Ruby scripts as `BUNDLE_GEMFILE=../../Gemfile bundle exec ruby <script>`; `generate.sh` sets this itself.)

## Type overrides (Gson coercion)
Types come from the Java declarations, with one exception: java-slack-sdk relies on Gson coercing JSON numbers into `String` fields (and so on), which Swift's `JSONDecoder` does not do. Where values recorded in the upstream fixtures (`json-logs/samples/api/*.json`) contradict the Java type, the field is listed in `type_overrides.yml` (one explicit entry per Java field: type, Java declaration, reason, fixture evidence). `gen_openapi.rb` emits the override type plus a `description` (a `///` doc comment in the generated Swift: "Type differs from java-slack-sdk: ...") and fails if an entry names a class or field that no longer exists or whose declared type changed. `scan_mismatch.rb` exits non-zero on any fixture mismatch without an entry; mismatches seen only in the slack-api-ref docs examples are printed for information and keep Java's type. Note the fixture generator also writes Java-typed placeholders (`""`, `123`) into the same fields, so strict decoding of those fixtures fails at overridden fields; real responses carry the recorded type. `java_placeholders.rb` therefore drops exactly those values (key marked `x-java-type`, value equal to what `ObjectInitializer.initProperties` writes: string `""`, integer `123`, number `12.3`, boolean `false`) from the fixtures before decoding; `prepare_inputs.rb` and `decode_all.rb` use it, `scan_mismatch.rb` shares its placeholder test. Nothing else is stripped.

## All-methods fixture decode (`decode_all.rb`)
299/334 fixtures decode both with and without stripping, but the failures move: without it 12 fixtures stop at an overridden field (`thumb_360_w`: `files.info`, `files.list`, `search.all`, ...); with it none do, and those fixtures reach the next problem. The 35 remaining failures are outside the overrides: 34 are placeholders the recorder wrote into hand-written SlackBlockKit types (block element `url` `""` is an invalid URL: 23; block/view/rich-text `type` `""`: 11 incl. 4 `views.*`), and `agents.conversations.listViews` (Java declares `List<View>`, the fixture holds agent views without `type`). Stripping these would need the SlackBlockKit schemas, which the document does not describe. The 5-method DecodeCheck reports are unchanged.

## Decode (new = Java-derived; old = swift-slack today). dropped = payload paths lost in decode->encode (leaf-most)
| method | live new/old | fixture new/old | docs new/old |
|---|---|---|---|
| team.info | ok 0 / ok 8 | ok 0 / ok 15 | ok 0 / ok 5 |
| users.info | ok 0 / ok 0 | ok 0 / ok 9 | ok 0 / ok 0 |
| conversations.list | ok 1 (parent_conversation:null) / ok 4 | ok 1 (callstack) / ok 6 | ok 0 (both examples) / ok 3, 2 |
| chat.postMessage | ok 0 / ok 2 | FAIL message.blocks[0].elements[0].url "Invalid URL string" / FAIL (same, attachments[].blocks) | ok 0 / ok 0 |
| admin.conversations.getConversationPrefs | no live | ok 0 / ok 6 | ex1 FAIL prefs.who_can_post.type (string where Java has List<String>) / ok 2 ; ex2 ok 0 / ok 4 |
