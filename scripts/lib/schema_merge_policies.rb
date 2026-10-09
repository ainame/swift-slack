require_relative './schema_merge'

# Per-name merge decisions for nested response schemas; see schema_merge.rb.
# Names that no fixture defines differently, and hand-written models, need no entry.

# Nested names whose fixtures define different property sets and still resolve by
# last fixture wins, as before the policy table existed. They were seeded from the
# first generation that ran the collision guard, so generated output is unchanged.
# Move a name out of this list by giving it a `union` policy below, a hand-written
# model in Sources/SlackModels, or a ref fixer. Tracked in swift-slack#177.
KNOWN_COLLISION_ISSUE = '#177'.freeze
KNOWN_COLLISIONS = %w[
  Accessory Attachment Bot BotProfile Canvas Cc Channel Column Comment Config
  CreationSource Data DefaultValueTyped Description DescriptionBlockElement Element
  ElementConfirm Error Field Fields File FileElement Filter Function Group Grouping
  IM Icon Icons InviteRequest Item ItemMessage Latest List ListLimits ListMetadata
  Match MediaProgress Message MessageBlock MessageElement MessageFile MessageIcons
  Metadata Option OptionGroup Options Paging Permission Prefs Preview Private
  Profile Public PurpleElement PurpleIcons PutParameter Reaction Record RecordField
  Reminder RestrictedTo Root SchemaOptions Scopes Section Self Shares Style Tab Team
  Transcription Trigger User
].freeze

MERGE_POLICIES = {
  # ConversationProperties. quicktype names nested types differently per fixture
  # (Canvas/PropertiesCanvas, Tab/Tabz, *RestrictedTo/RestrictedTo), so these
  # four fields keep the last fixture's reference, as they did before this table.
  'Properties' => SchemaMergePolicy.union(last_wins: %w[canvas posting_restricted_to tabz threads_restricted_to]),
  # Every cursor-paginated method; fixtures carry subsets of {messages, warnings, next_cursor}.
  'ResponseMetadata' => SchemaMergePolicy.union,
}.merge(
  KNOWN_COLLISIONS.to_h { [_1, SchemaMergePolicy.known_collision(KNOWN_COLLISION_ISSUE)] }
).freeze
