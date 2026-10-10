# Java-derived Web API types: prototype report

Repositories are named in full: **upstream java-slack-sdk** (Java models and recorded JSON fixtures), **upstream slack-api-ref** (Slack's method docs and examples), **Apple's swift-openapi-generator** (1.11.0, as pinned in `Tools/`), and **downstream swift-slack** (this repository).

## Summary

The prototype generates downstream swift-slack's Web API response types from the upstream java-slack-sdk Java classes instead of inferring them from the upstream java-slack-sdk fixtures. The Java sources are parsed with tree-sitter into an OpenAPI document, and Apple's swift-openapi-generator turns that into Swift.

What it shows:

- **It covers the whole API.** All 334 methods with a Java response class become 418 schemas and about 79.6k lines of Swift, and the result compiles. With the recorder's placeholders replaced or stripped, all 334 upstream fixtures decode.
- **Today's type defects go away at the source.** Same-named schemas are no longer merged last-wins, placeholder values no longer decide types or names, and `type` is no longer forced to be required.
- **Call sites keep their shape.** Requests and the client layer are unchanged. Response properties keep their names. The differences are type names that apps spell out, some field types, and more fields being available (see Library user impact).
- **It is not source compatible.** Of 4,826 compared response properties, 62% are unchanged, 9% move to another type name, 2% change type, 8% exist today but not in the new type, and 19% are new.

Open decisions:

1. **Release strategy** (undecided). One idea is a new target alongside the existing Web API types. Events (`SlackApp`) still use today's `SlackModels` types, so a Web API `Message` and an event `Message` would be different types until Events move too.
2. **`Payload` naming** produced by Apple's swift-openapi-generator for nested types (`User.ProfilePayload`, and `...PayloadPayload` for array elements). It is accepted for the prototype.
3. **Legacy methods.** The 71 methods that exist only in the new output (legacy `channels.*`, `groups.*`, `im.*`, `mpim.*`, ...) have upstream java-slack-sdk response classes. Today's pipeline excludes them through `UNSUPPORTED_METHODS`, so the same exclusion would need applying.

## Why

Today's pipeline (downstream swift-slack `scripts/`) runs quicktype over each upstream java-slack-sdk fixture (`json-logs/samples/api/*.json`) and merges the results into one global schema namespace. The 2026-10-09 audit (#177) traced most of its defects to three causes:

- **Last-wins merge.** Nested schema names such as `Team`, `User` or `ResponseMetadata` are shared across all methods, and the alphabetically last fixture's shape replaces the others. For example, `SlackModels.Team` has only `id` and `name`, and `ResponseMetadata` lost `next_cursor` (#199).
- **Placeholder values decide types.** The fixtures are recorded real responses merged with objects that upstream java-slack-sdk's recorder fills with Java-typed placeholders (`ObjectInitializer.initProperties`: `""`, `123`, `12.3`, `false`). quicktype infers types from those values: String for numbers, single-case enums from fake IDs, and fixed-key structs for maps (`FailedUserIDS` with keys `U00000000`/`U00000001`). It also produces odd names (`IngTeam`, `TingUser`).
- **Forced required `type`.** A generator visitor makes every string `type` property required, but several objects arrive without it.

The Java classes are what upstream java-slack-sdk actually deserializes into. They name every field, including ones no fixture populated.

## Approach

    upstream java-slack-sdk .java -> tree-sitter syntax tree -> OpenAPI 3.1 (openapi.json) -> Apple's swift-openapi-generator -> Swift

- **Responses.** Each `<Method>Response` class under `com.slack.api.methods.response` becomes the 200 schema of `POST /<method>`. Eight classes don't follow that naming (`ApiTestResponse`, `oauth.v2.*`, `openid.connect.*`, `rtm.*`) and need an explicit map.
- **Shared versus nested.** Top-level classes in `com.slack.api.model` become shared named schemas (`Components.Schemas.User`, `.Team`, `.Conversation`, `.Message`, `.File`, ...). Java inner classes become inline schemas, which Apple's swift-openapi-generator nests in the parent and names `<PropertyName>Payload`. Same-named inner classes in different responses therefore never collide.
- **Everything is optional except `ok`.** Slack omits fields depending on the endpoint, the object's kind (channel vs DM, human vs workflow bot), the request arguments (`include_locale`) and the plan. Java declarations carry no nullability (no `@Nullable`, and primitive `boolean` defaults to false), and the fixtures contain no `null` at all.
- **JSON keys** follow Gson: `@SerializedName` if present, otherwise snake_case of the field name. Superclass fields come first.
- **Block Kit.** Types that upstream java-slack-sdk reads through Gson type adapters (`LayoutBlock`, `View`, `TextObject`, `RichTextBlock`, ...) become placeholder schemas. Swift-openapi-generator's `typeOverrides` maps them to downstream swift-slack's hand-written SlackBlockKit types. Inner classes that merely share a name, such as `AgentsConversationsListViewsResponse.View`, are not remapped.
- **Parsing and name resolution.** `gen_openapi.rb` walks the tree-sitter syntax tree, using the `ruby_tree_sitter` gem and the `vendor/tree-sitter-java` grammar. Type names resolve in five steps:
  1. nested classes of the current and enclosing classes;
  2. single-type imports;
  3. the same package;
  4. wildcard imports;
  5. fully qualified names.

  Syntax errors, unmodelled Java constructs and unresolved type names raise with file and line, except a short list of external types that are deliberately untyped.

## Type overrides

Policy:

1. Generate everything from the Java declarations.
2. Override only where values recorded in the upstream java-slack-sdk fixtures contradict the Java type. This typically happens because Gson coerces a JSON number into a Java `String`, which Swift's `JSONDecoder` does not do. A value of another type than the declaration can only come from a recorded response, because the recorder's own placeholders always match the Java type.
3. Ignore mismatches seen only in upstream slack-api-ref docs examples; Java's type stays.

`type_overrides.yml` has 43 explicit entries, one per Java field (`<Java class>#<JSON key>`), each with the new type, the Java declaration, a reason and the fixtures that recorded the value.

- **Main entries.** The largest group is `File` and search-match image sizes (`original_w`, `thumb_360_w`, ...), which are `String` in Java and `Int` here. Others are `created`, `timestamp`, `score`, `session_id`, `channel_actions_ts` and `cache_ts` (`Int`), `permalink_public` and `url_private_download` (`String`), and `Attachment.video_html` and Lists cell `value` (untyped).
- **Doc comments.** `gen_openapi.rb` emits a `description` that Apple's swift-openapi-generator renders as a `///` comment:

      /// Type differs from java-slack-sdk: `File.thumb360Width` is declared `String`, but recorded responses send integers.
      public var thumb360W: Swift.Int?

- **Stale entries.** It fails if an entry names a missing class or field, or if the Java declaration changed.
- **Mismatch scan.** `scan_mismatch.rb` exits non-zero on any fixture mismatch without an entry.

## Placeholder stripping

The recorder also wrote Java-typed placeholders into the overridden fields (`original_w: ""`), so strict decoding of those fixtures would fail there even though real responses carry numbers. `java_placeholders.rb` removes exactly those values before decoding: a key marked `x-java-type` whose value equals the recorder's placeholder for that Java type (`""`, `123`, `12.3`, `false`). Nothing else is stripped there. `prepare_inputs.rb`, `decode_all.rb` and `scan_mismatch.rb` share it.

**Block Kit placeholders.** The same recorder also fills the hand-written SlackBlockKit subtrees (the schemas mapped through `typeOverrides`: `Block`, `View`, `TextObject`, `RichTextBlock`, including arrays of them), which the generated schemas do not describe. Inside those subtrees only, `java_placeholders.rb` replaces `""` in URL fields (`url`, `image_url`, `title_url`, `provider_icon_url`, `video_url`, `thumbnail_url`) with `https://example.com`, an empty text-object `type` with `plain_text`, and an empty rich text list `style` with `bullet`; an empty optional button or confirm `style` is dropped. SlackBlockKit and the generated types are not changed. `decode_all.rb` prints the replacement count (24,862).

## SlackBlockKit changes

Eight hand-written SlackBlockKit enums (`Block`, section accessory, context, actions and input elements, two rich-text element enums, `View`) used to throw on an unknown `type`. That made a single unfamiliar block fail the whole response. They now decode it as `.unknown(type: String, payload: OpenAPIObjectContainer)` and encode it back unchanged, following `SlackModels.Container`.

Invalid URL strings in Block Kit (`url: ""`) still throw, deliberately: such strings only appear as fixture placeholders, which the decode preprocessing fixes (see Placeholder stripping).

## Results

### All methods (`decode_all.rb`)

| step | result |
|---|---|
| Java -> OpenAPI -> Swift | 334 methods, 418 schemas, ~79.6k lines, compiles |
| Decode upstream java-slack-sdk fixtures, placeholders replaced or stripped | 334 / 334 (310 before the Block Kit rule, 299 before the SlackBlockKit change) |

### Static scan (`scan_mismatch.rb`)

| group | count |
|---|---|
| fixture mismatches explained by an override | 87 |
| recorder placeholders at overridden fields | 1,022 |
| unexplained fixture mismatches | 0 |
| mismatches only in upstream slack-api-ref docs examples (information) | 16 |

### Five methods, new vs old

`dropped` counts payload paths that a decode-then-encode round trip loses. The columns are:

- **old:** downstream swift-slack today.
- **live:** responses recorded from one workspace with a bot token (not committed).
- **fixture:** upstream java-slack-sdk fixtures.
- **docs:** upstream slack-api-ref examples.

| method | live new / old | fixture new / old | docs new / old |
|---|---|---|---|
| team.info | 0 / 8 | 0 / 15 | 0 / 5 |
| users.info | 0 / 0 | 0 / 9 | 0 / 0 |
| conversations.list | 1 / 4 | 1 / 6 | 0, 0 / 3, 2 |
| chat.postMessage | 0 / 2 | 181 / FAIL | 0 / 0 |
| admin.conversations.getConversationPrefs | (no live) | 0 / 6 | example 1 FAIL / 2; example 2 0 / 4 |

- **`conversations.list`:** the 1 live drop is `parent_conversation: null` disappearing on re-encode, and the 1 fixture drop is `callstack`, which Java doesn't declare.
- **`chat.postMessage`:** the new types decode the fixture now that Block Kit placeholders are replaced; the old types still fail on `url: ""`. All 181 fixture drops are keys inside Block Kit objects that the hand-written SlackBlockKit types do not model (the recorder fills every field of every block).
- **`getConversationPrefs`:** the docs example 1 failure is the docs sending a string where Java declares `List<String>`.

## Library user impact

### Call sites

The request side (method arguments from upstream slack-api-ref) and the client layer are unchanged. The response schemas keep their names through `typeOverrides` typealiases (`Components.Schemas.ChatPostMessageResponse`). Property names come from JSON keys under the same naming strategy. Typical code therefore reads the same, and gains fields:

```swift
let response = try await slack.client.conversationsList(body: .json(.init(limit: 100)))
let json = try response.ok.body.json
for channel in json.channels ?? [] {
    print(channel.name, channel.isMember, channel.numMembers)  // today: no isMember / numMembers
}
let cursor = json.responseMetadata?.nextCursor                  // today: no nextCursor (#199)
```

Apps notice changes in these places:

- **Spelled-out type names.** Parameters and stored properties that name a model type change, for example `func render(_ channel: SlackModels.Channel)` becomes `func render(_ channel: Components.Schemas.Conversation)`.
- **Long nested names.** Inner-class types have long names (`AdminConversationsGetConversationPrefsResponse.PrefsPayload.WhoCanPostPayload`), but property chains hide them (`json.prefs?.whoCanPost?.type`).
- **Overridden fields** change type (`file.originalW` becomes `Int?`).
- **`Message.type`** becomes optional.
- **Block Kit switches** must handle `.unknown`.
- **Event types differ.** Events keep today's `SlackModels` types.

These snippets follow the generated declarations; DemoApps was not rebuilt against a prototype-backed client.

### API diff (`api_diff.rb`, `reports/api-diff.md`)

The diff compares the 263 `<Method>Response` types present in both, walking properties by JSON key through the referenced types. Each (type pair, JSON key) is counted once.

| category | properties | responses touching it |
|---|---:|---:|
| unchanged | 3,000 | |
| renamed or moved type | 441 | 160 |
| scalar or shape changed | 85 | 128 |
| removed (exists today) | 381 | 45 |
| added | 919 | 195 |

In total, 97 of the 263 responses have no renamed, changed or removed property, and 166 have at least one. Optionality differs on 28 properties, all of which go from required to optional.

- **Renames (441).** 168 are moves only (`SlackModels.User` to `Components.Schemas.User`, and likewise `File`, `Message`, `Attachment`, ...). 104 go to another shared schema:
  - `Channel` to `Conversation`.
  - `FileElement` and `ItemFile` to `File`, so three file types become one.
  - `IngTeam` to `ConnectTeam`.
  - `ResponseMetadata` to `ErrorResponseMetadata` or `WarningResponseMetadata` (the Java class used depends on the method).

  The other 169 go to a nested `...Payload` type (`UserProfile` to `User.ProfilePayload`, `Prefs` to `...PrefsPayload`).
- **Type changes (85).** 44 are the `File` image sizes going from `String` to `Int`. Untyped maps become typed structs, and `warnings` becomes `[String]`.
- **Removed (381).** Most removals pair an old shared type with a slimmer Java inner class. Real removals to review include `users.info` `UserProfile.name` and `getConversationPrefs` `Prefs.channels`/`groups`. The latter were usergroup fields that the last-wins merge had put there.
- **Added (919).** These are fields today's types silently drop: `Team.domain`/`icon`/`url`, `Conversation.is_member`/`num_members`, `ResponseMetadata.next_cursor`, `prefs.who_can_post`, ...

### Migration difficulty

- **Mechanical (find and replace).** The moved types and the named shared-type renames. Property names inside them are unchanged.
- **Local edits.**
  - `File` sizes are now `Int`.
  - Reads of removed properties need replacing.
  - The `ResponseMetadata` variant depends on the method.
  - 28 properties that were required are now optional.
- **Awkward.**
  - Helper signatures that name nested `Payload` types.
  - Stored or cached `SlackModels` values.
  - Code that passes values between Web API responses and Events.
- **Overall.** The effort scales with how many model types an app names in its own signatures, not with how many Web API calls it makes.

## Known limitations

- **Payload naming.** Apple's swift-openapi-generator derives inline type names from the property name plus the constant `inlineTypeSuffix` (`Payload`); arrays of inline objects get it twice. Neither `nameOverrides` nor any other option up to 1.14.0 changes this. An upstream fix would have to be opt-in, for example using the JSON Schema `title` as the type name.
- **Gson adapters** other than Block Kit (audit-log values, workflow step inputs, `File` adapter quirks) are untyped. `gen-report.json` lists `unknown_types` and `untyped_adapter`.
- **Docs-only mismatches** from upstream slack-api-ref examples are ignored by policy (16 are listed for information). Several are clear docs errors, such as `"is_bot": "string"`.
- **Coverage of the evidence.**
  - The live check covered one workspace, a bot token and a few methods.
  - Fixtures are one sample per method.
  - The API diff is static: it treats unions and enums as leaves and ignores hand-written types that lack the generator's remark comments.

## How to run

Run from `Prototypes/JavaOpenAPI`. The repository root first needs `bundle install`, `git submodule update --init` and `swift build --package-path ../../Tools`. The tree-sitter grammar is built by `make tree-sitter-java` at the root; `generate.sh` runs it, and `TREE_SITTER_JAVA_LIB=<path>` points at another build. Run the Ruby scripts as `BUNDLE_GEMFILE=../../Gemfile bundle exec ruby <script>`.

```sh
sh generate.sh                    # Java -> openapi.json -> Sources/JavaProtoTypes/Types.swift (5 methods)
ruby prepare_inputs.rb            # fills inputs/ (git-ignored); optional LIVE_RESPONSES=<dir>
swift build
for k in live fixtures docs; do .build/debug/DecodeCheck inputs/$k reports/new-$k.json; done
(cd OldHarness && swift build && for k in live fixtures docs1 docs2; do .build/debug/Harness ../inputs/$([ $k = live ] && echo live || echo old-$k) ../reports/old-$k.json; done)
ruby scan_mismatch.rb             # static JSON-vs-schema check; exits non-zero on unexplained fixture mismatches
ruby decode_all.rb                # all 334 methods: regenerate all/, build all/pkg, decode fixtures (--raw: no stripping)
ruby api_diff.rb                  # needs all/out from decode_all.rb; writes reports/api-diff.md
```

## Files

| file | purpose |
|---|---|
| `gen_openapi.rb` | Java (tree-sitter) to OpenAPI |
| `type_overrides.yml` | the 43 overrides |
| `generate.sh`, `openapi-generator-config.yaml`, `openapi.json`, `gen-report.json` | five-method generation |
| `Sources/JavaProtoTypes/Types.swift` | generated Swift |
| `Sources/DecodeCheck/` | decode check against the prototype types |
| `OldHarness/` | the same check against today's types |
| `prepare_inputs.rb`, `java_placeholders.rb` | decode inputs and placeholder stripping |
| `scan_mismatch.rb` | static mismatch scan |
| `decode_all.rb`, `all/` | all-methods generation and decode (`all/out` and `all/pkg` are git-ignored) |
| `api_diff.rb`, `reports/api-diff.md` | old vs new API diff |
| `reports/{new,old}-*.json` | decode results |
