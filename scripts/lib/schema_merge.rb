require_relative './slack_model_catalog'

# quicktype runs once per java-slack-sdk fixture, so every fixture names its own
# nested definitions (ResponseMetadata, Team, Profile, ...). All of them end up in
# one shared components/schemas, and nested names are NOT unique across Slack
# methods: some are the same object seen with different fields (ResponseMetadata),
# others are unrelated models that happen to share a name (Workflow, Error).
#
# Each nested schema name that more than one fixture defines with a different
# property set therefore needs an explicit decision, recorded in MERGE_POLICIES:
#
#   union           The fixtures describe one object. Property sets are unioned
#                   recursively (see SchemaMerge.union).
#   known_collision Today's behaviour: the alphabetically last fixture wins and
#                   fields seen elsewhere are dropped. Every entry cites the
#                   tracking issue and is meant to move to `union`, a hand-written
#                   model in Sources/SlackModels, or a ref fixer.
#
# A colliding name with no policy fails generation (swift-slack#178). Names of
# hand-written models in Sources/SlackModels are exempt: ref fixers already point
# their users at an empty placeholder schema.
module SchemaMergePolicy
  # last_wins: top-level property names whose schemas conflict between fixtures
  # and are resolved by keeping the last fixture's schema, as before the policy
  # table existed. Each one is a known defect to remove, not a design choice.
  def self.union(last_wins: [])
    { policy: :union, last_wins: last_wins.freeze }.freeze
  end

  def self.known_collision(issue)
    { policy: :known_collision, issue: issue }.freeze
  end
end

class SchemaMergeError < StandardError; end

module SchemaMerge
  # Merge two schemas that describe the same value.
  # - identical schemas are kept;
  # - an untyped schema (inferred from an empty sample) yields to a concrete one;
  # - objects union their properties; `required` keeps only names required by both;
  # - arrays merge their item schemas;
  # - anything else is a conflict and raises SchemaMergeError.
  def self.union(left, right, path, last_wins: [])
    return left if left == right
    return right if untyped?(left)
    return left if untyped?(right)

    if object?(left) && object?(right)
      union_objects(left, right, path, last_wins)
    elsif left['type'] == 'array' && right['type'] == 'array' && left['items'].is_a?(Hash) && right['items'].is_a?(Hash)
      left.merge(right, 'items' => union(left['items'], right['items'], "#{path}[]"))
    else
      raise SchemaMergeError,
            "#{path}: cannot union #{left.to_json} with #{right.to_json}"
    end
  end

  # quicktype infers `items: {}` from an empty array and an object with no
  # properties from an empty object; neither says anything about the real type.
  def self.untyped?(schema)
    return true if schema.is_a?(Hash) && schema['type'] == 'array' && schema['items'] == {}

    schema.is_a?(Hash) && schema['type'] == 'object' && (schema['properties'].nil? || schema['properties'] == {})
  end

  def self.object?(schema)
    schema.is_a?(Hash) && schema['type'] == 'object' && schema['properties'].is_a?(Hash)
  end

  def self.union_objects(left, right, path, last_wins = [])
    properties = left['properties'].dup
    right['properties'].each do |key, schema|
      properties[key] =
        if !properties.key?(key) || last_wins.include?(key)
          schema
        else
          union(properties[key], schema, "#{path}.#{key}")
        end
    end

    merged = left.merge(right).merge('properties' => properties)
    if left.key?('required') || right.key?('required')
      merged['required'] = (left['required'] || []) & (right['required'] || [])
    end
    merged
  end

  def self.property_keys(schema)
    schema.is_a?(Hash) && schema['properties'].is_a?(Hash) ? schema['properties'].keys : []
  end

  def self.summarize(fixtures)
    shown = fixtures.first(4).join(', ')
    fixtures.size > 4 ? "fixtures: #{shown}, ... (#{fixtures.size} total)" : "fixtures: #{shown}"
  end

  # Merge the per-fixture `definitions` into one schema map.
  #
  # definitions_by_fixture: { 'conversations.list' => { 'ResponseMetadata' => {...} } },
  #   merged in the given order (the last definition wins for known collisions).
  # Raises SchemaMergeError listing every problem at once.
  def self.merge_all(definitions_by_fixture, policies:, handwritten: SlackModelCatalog.handwritten_types)
    handwritten = handwritten.flat_map { [_1, SlackModelCatalog.emitted_name(_1)] }.uniq
    schemas = {}
    fixtures = Hash.new { |hash, name| hash[name] = [] }
    differing_keys = Hash.new { |hash, name| hash[name] = [] }
    failures = []

    definitions_by_fixture.each do |fixture, definitions|
      definitions.each do |name, incoming|
        fixtures[name] << fixture
        unless schemas.key?(name)
          schemas[name] = incoming
          next
        end

        existing = schemas[name]
        policy = policies.dig(name, :policy)
        case policy
        when :union
          begin
            schemas[name] = union(existing, incoming, name, last_wins: policies.dig(name, :last_wins) || [])
          rescue SchemaMergeError => error
            failures << "#{error.message} (merging fixture #{fixture}; #{summarize(fixtures[name])})"
          end
        when :known_collision
          schemas[name] = incoming
        when nil
          unless handwritten.include?(name)
            before = property_keys(existing)
            after = property_keys(incoming)
            keys = (before | after) - (before & after)
            differing_keys[name] |= keys
          end
          schemas[name] = incoming
        else
          raise ArgumentError, "Unknown merge policy #{policy.inspect} for #{name}"
        end
      end
    end

    differing_keys.each do |name, keys|
      next if keys.empty?

      failures << "#{name}: fixtures define it with different properties and it has no merge policy " \
                  "(differing keys: #{keys.sort.join(', ')}; #{summarize(fixtures[name])}). " \
                  'Add it to MERGE_POLICIES in scripts/lib/schema_merge_policies.rb as `union`, or ' \
                  'give it a hand-written model or ref fixer.'
    end
    raise SchemaMergeError, "Nested schema merge failed:\n- #{failures.uniq.join("\n- ")}" unless failures.empty?

    schemas
  end
end
