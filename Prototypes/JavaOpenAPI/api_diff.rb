#!/usr/bin/env ruby
# frozen_string_literal: true

# Mechanical API diff of Web API response types: downstream swift-slack today ("old") vs the
# Java-derived prototype ("new"). Both are swift-openapi-generator output (plus hand-written
# SlackModels types), so this reads the Swift sources rather than the OpenAPI documents.
#
# Usage (from Prototypes/JavaOpenAPI, needs all/out/Types.swift from decode_all.rb):
#   ruby api_diff.rb [--out reports/api-diff.md]
#
# For every `<Method>Response` present in both, it walks properties by JSON key through the types they
# reference and classifies each (type pair, JSON key) once:
#   unchanged   same type
#   renamed     both are model types with different qualified names (moved = same simple name, other namespace)
#   changed     scalar / array / dictionary / model shape differs (String -> Int, [String] -> String, model -> String)
#   removed     only the old type has the key
#   added       only the new type has the key
# Optionality (T vs T?) is tracked separately.
#
# Limitations are listed at the end of the generated report.

require "set"
require "optparse"

ROOT = File.expand_path("../..", __dir__)
OLD_FILES = Dir[File.join(ROOT, "Sources/SlackClient/WebAPI/Generated/Components/*.swift")] +
            Dir[File.join(ROOT, "Sources/SlackModels/**/*.swift")]
NEW_FILE = File.join(__dir__, "all/out/Types.swift")
FIVE = %w[TeamInfoResponse UsersInfoResponse ConversationsListResponse ChatPostMessageResponse
          AdminConversationsGetConversationPrefsResponse].freeze

# ---- Swift source model -------------------------------------------------------------------------

Property = Struct.new(:key, :name, :type, :optional)
SwiftType = Struct.new(:qname, :kind, :properties, :coding_keys)

# Reads the subset of Swift that swift-openapi-generator and the hand-written models use:
# struct/enum/extension nesting by brace depth, `public var`, typealias, CodingKeys, and the
# `/// - Remark: Generated from `#/components/schemas/...`` comment that carries the JSON key.
class SwiftIndex
  DECL = /^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|internal|private|fileprivate|package|indirect|final|open)\s+)*(struct|enum|class|extension)\s+([\w.`]+)/
  PROPERTY = /^\s*public\s+(?:var|let)\s+`?(\w+)`?\s*:\s*([^={]+?)\s*(?:=.*|\{)?$/
  ALIAS = /^\s*(?:public\s+)?typealias\s+(\w+)\s*=\s*(.+?)\s*$/
  REMARK = %r{Remark: Generated from `#/components/schemas/([^`]+)`}

  attr_reader :types

  def initialize(module_prefix_for)
    @module_prefix_for = module_prefix_for
    @types = {}
    @aliases = {}
  end

  def add_file(path)
    prefix = @module_prefix_for.call(path)
    stack = [] # {qname:, open_depth:}
    depth = 0
    remark_key = nil
    File.foreach(path, encoding: "UTF-8") do |line|
      if (m = line.match(REMARK))
        remark_key = m[1].split("/").last
        next
      end
      next if line.lstrip.start_with?("//")

      code = line.gsub(/"(?:[^"\\]|\\.)*"/, '""').sub(%r{//.*}, "")
      top = stack.last
      in_body = top && depth == top[:open_depth] + 1

      if (m = code.match(DECL))
        name = m[2].delete("`")
        qname = declared_name(m[1], name, stack, prefix)
        stack << { qname: qname, open_depth: depth, coding_keys: name == "CodingKeys" && m[1] == "enum" }
        unless stack.last[:coding_keys]
          @types[qname] ||= SwiftType.new(qname, m[1] == "enum" ? :enum : :struct, [], {})
          @types[qname].kind = :enum if m[1] == "enum"
        end
      elsif in_body && top[:coding_keys]
        record_coding_key(top[:qname], line)
      elsif in_body && (m = code.match(ALIAS))
        @aliases["#{top[:qname]}.#{m[1]}"] = { target: m[2], scope: top[:qname] }
      elsif in_body && (remark_key || !code.include?("{")) && (m = code.match(PROPERTY)) && @types[top[:qname]]&.kind == :struct
        optional = m[2].strip.end_with?("?")
        key = remark_key || m[1]
        @types[top[:qname]].properties << Property.new(key, m[1], m[2].strip, optional)
      elsif code.match?(/public var additionalProperties/) && in_body
        @types[top[:qname]]&.properties&.push(Property.new("*", "additionalProperties", code[/:\s*(.+?)\s*$/, 1], false))
      end
      remark_key = nil unless code.strip.empty?

      depth += code.count("{") - code.count("}")
      stack.pop while stack.any? && depth <= stack.last[:open_depth]
    end
  end

  # Applies hand-written CodingKeys (`case swiftName = "json_key"`) to properties without a Remark key.
  def finish
    @types.each_value do |type|
      type.properties.each do |p|
        p.key = type.coding_keys[p.name] if p.key == p.name && type.coding_keys[p.name]
      end
    end
  end

  # Resolves a type as written inside `scope` to [container wrappers, name, model?], following typealiases.
  # `name` is the qualified declaration (when found in the sources) or the normalised name as written.
  def resolve(type_text, scope)
    wrappers, base = strip_wrappers(type_text)
    8.times do
      declaration = find_declaration(base, scope)
      alias_entry = declaration && @aliases[declaration]
      break unless alias_entry

      inner_wrappers, base = strip_wrappers(alias_entry[:target])
      wrappers += inner_wrappers
      scope = alias_entry[:scope]
    end
    declaration = find_declaration(base, scope)
    [wrappers, declaration || base.sub(/\A(?:Swift|SlackBlockKit)\./, "").sub(/\A(String|Int|Bool|Double)\z/, 'Swift.\\1').sub(/\ASwift\./, ""), declaration && @types[declaration]&.kind == :struct]
  end

  private

  # Qualified name of the struct, enum or typealias a name written inside `scope` refers to (innermost scope first).
  def find_declaration(name, scope)
    parts = scope.split(".")
    parts.size.downto(0) do |i|
      candidate = (parts.first(i) + [name]).join(".")
      return candidate if @types.key?(candidate) || @aliases.key?(candidate)
    end
    nil
  end

  def declared_name(keyword, name, stack, prefix)
    return name if keyword == "extension" && stack.empty?
    return "#{prefix}.#{name}".sub(/\A\./, "") if stack.empty?

    "#{stack.last[:qname]}.#{name}"
  end

  def record_coding_key(owner, code)
    parent = owner.sub(/\.CodingKeys\z/, "")
    return unless (type = @types[parent])

    code.scan(/case\s+`?(\w+)`?\s*=\s*"([^"]+)"/) { |swift_name, json| type.coding_keys[swift_name] = json }
  end

  def strip_wrappers(type)
    s = type.strip.sub(/[?!]\z/, "")
    wrappers = []
    while (m = s.match(/\A\[(.+)\]\z/))
      inner = m[1]
      colon = top_level_colon(inner)
      if colon
        wrappers << :dict
        s = inner[(colon + 1)..].strip.sub(/\?\z/, "")
      else
        wrappers << :array
        s = inner.strip.sub(/\?\z/, "")
      end
    end
    [wrappers, s]
  end
  public :strip_wrappers

  def top_level_colon(text)
    nesting = 0
    text.each_char.with_index do |c, i|
      nesting += 1 if "[<(".include?(c)
      nesting -= 1 if "]>)".include?(c)
      return i if c == ":" && nesting.zero?
    end
    nil
  end
end

old_index = SwiftIndex.new(->(path) { path.include?("/Sources/SlackModels/") ? "SlackModels" : "" })
OLD_FILES.each { |f| old_index.add_file(f) }
old_index.finish
new_index = SwiftIndex.new(->(_) { "" })
abort "#{NEW_FILE} missing: run decode_all.rb first" unless File.exist?(NEW_FILE)
new_index.add_file(NEW_FILE)
new_index.finish

# ---- Diff ---------------------------------------------------------------------------------------

Entry = Struct.new(:category, :detail, :old_parent, :new_parent, :key, :old_type, :new_type, :path, :optionality)

class Differ
  def initialize(old_index, new_index)
    @old = old_index
    @new = new_index
    @pair_entries = {}  # [old_q, new_q] => [Entry]
    @pair_children = {} # [old_q, new_q] => [[key, child_pair]]
  end

  attr_reader :pair_entries, :pair_children

  def model?(index, qname)
    qname && index.types[qname]&.kind == :struct
  end

  # Direct (non-recursive) comparison of two struct types.
  def compare_pair(pair)
    return if @pair_entries.key?(pair)

    old_q, new_q = pair
    entries = []
    children = []
    old_props = @old.types[old_q].properties.to_h { |p| [p.key, p] }
    new_props = @new.types[new_q].properties.to_h { |p| [p.key, p] }
    (old_props.keys | new_props.keys).each do |key|
      op = old_props[key]
      np = new_props[key]
      if op && np
        child = compare_property(pair, key, op, np, entries)
        children << [key, child] if child
      else
        entries << Entry.new(op ? :removed : :added, nil, old_q, new_q, key, op&.type, np&.type)
      end
    end
    @pair_entries[pair] = entries
    @pair_children[pair] = children
  end

  private

  def compare_property(pair, key, op, np, entries)
    old_q, new_q = pair
    ow, oq, o_model = @old.resolve(op.type, old_q)
    nw, nq, n_model = @new.resolve(np.type, new_q)
    optionality = (op.optional != np.optional) ? [op.optional, np.optional] : nil
    add = lambda { |category, detail = nil|
      entries << Entry.new(category, detail, old_q, new_q, key, op.type, np.type, nil, optionality)
    }

    if ow != nw
      add.call(:changed, "container #{describe(ow)} -> #{describe(nw)}")
    elsif o_model && n_model
      add.call(*classify_model_names(oq, nq))
      # Show the resolved qualified names (with [] for each array/dictionary level), not the text as written.
      entries.last.old_type = oq + "[]" * ow.size
      entries.last.new_type = nq + "[]" * nw.size
      child = [oq, nq]
      compare_pair(child)
      return child
    elsif o_model != n_model
      add.call(:changed, "model <-> leaf")
    else
      add.call(oq == nq ? :unchanged : :changed, "leaf type")
    end
    nil
  end

  def classify_model_names(old_q, new_q)
    return [:unchanged] if old_q == new_q

    old_simple = old_q.split(".").last
    new_simple = new_q.split(".").last
    if old_simple == new_simple
      [:renamed, "moved"]
    elsif new_q.split(".").size > 3
      [:renamed, "to nested payload"]
    else
      [:renamed, "to other shared schema"]
    end
  end

  def describe(wrappers)
    wrappers.empty? ? "scalar" : wrappers.join("/")
  end
end

differ = Differ.new(old_index, new_index)
responses = ->(index) { index.types.keys.grep(/\AComponents\.Schemas\.\w+Response\z/).sort }
old_responses = responses.call(old_index)
new_responses = responses.call(new_index)
both = old_responses & new_responses

# Breadth-first from each response; remember the first JSON path that reaches each pair.
first_path = {}
reach = {} # response => Set of pairs
both.each do |resp|
  root = [resp, resp]
  differ.compare_pair(root)
  seen = Set[root]
  queue = [[root, ""]]
  until queue.empty?
    pair, path = queue.shift
    first_path[pair] ||= path
    differ.pair_children[pair].each do |key, child|
      next if seen.include?(child)

      seen << child
      queue << [child, [path, key].reject(&:empty?).join(".")]
    end
  end
  reach[resp] = seen
end

all_pairs = reach.values.reduce(Set.new, :|)
entries = all_pairs.flat_map do |pair|
  differ.pair_entries[pair].map do |e|
    e.path = [first_path[pair], e.key].reject(&:empty?).join(".")
    e
  end
end
by_category = entries.group_by(&:category)
cat = ->(name) { by_category.fetch(name, []) }

responses_with = Hash.new { |h, k| h[k] = Set.new }
reach.each do |resp, pairs|
  pairs.each do |pair|
    differ.pair_entries[pair].each { |e| responses_with[e.category] << resp unless e.category == :unchanged }
  end
end
breaking_responses = Set.new
reach.each do |resp, pairs|
  breaking = pairs.any? { |pair| differ.pair_entries[pair].any? { |e| %i[renamed changed removed].include?(e.category) } }
  breaking_responses << resp if breaking
end

short = ->(q) { q.sub("Components.Schemas.", "") }
fence = ->(s) { "`#{s}`" }

# ---- Report -------------------------------------------------------------------------------------

out = +""
out << "# API diff: swift-slack today vs the Java-derived prototype\n\n"
out << "Generated by `api_diff.rb`; do not edit. Old = downstream swift-slack `Sources/SlackClient/WebAPI/Generated/Components` + `Sources/SlackModels`; new = prototype `all/out/Types.swift` (swift-openapi-generator 1.11.0 over the Java-derived OpenAPI document).\n\n"

out << "## Headline\n\n"
out << "- `<Method>Response` types: #{old_responses.size} old, #{new_responses.size} new, #{both.size} in both\n"
out << "- #{all_pairs.size} distinct (old type, new type) pairs reached from those responses, #{entries.size} property comparisons (each (type pair, JSON key) counted once)\n\n"
out << "| category | properties | responses touching it |\n|---|---:|---:|\n"
%i[unchanged renamed changed removed added].each do |c|
  out << "| #{c} | #{cat.call(c).size} | #{c == :unchanged ? "-" : responses_with[c].size} |\n"
end
optionality = entries.select(&:optionality)
out << "\nOptionality differs (T vs T?) on #{optionality.size} properties (#{optionality.count { |e| e.optionality == [false, true] }} required -> optional, #{optionality.count { |e| e.optionality == [true, false] }} optional -> required).\n\n"
out << "Responses with at least one renamed, changed or removed property reachable: #{breaking_responses.size} of #{both.size}. "
out << "Responses with no such difference: #{(both.to_set - breaking_responses).size}.\n\n"
out << "Only in old: #{(old_responses - new_responses).map { |q| fence.call(short.call(q)) }.join(", ").then { |s| s.empty? ? "none" : s }}\n\n"
out << "Only in new: #{(new_responses - old_responses).map { |q| fence.call(short.call(q)) }.join(", ").then { |s| s.empty? ? "none" : s }}\n\n"

out << "## Renamed or moved model types\n\n"
renamed = cat.call(:renamed).group_by { |e| [e.detail, e.old_type, e.new_type] }
out << "Properties whose model type changed (a rename counts once per referencing property; `[]` marks array or dictionary elements).\n\n"
out << "| kind | old | new | properties |\n|---|---|---|---:|\n"
renamed.sort_by { |_, v| -v.size }.first(40).each do |(detail, ot, nt), v|
  out << "| #{detail} | #{fence.call(short.call(ot))} | #{fence.call(short.call(nt))} | #{v.size} |\n"
end
out << "\nBy kind: " + cat.call(:renamed).group_by(&:detail).map { |d, v| "#{d} #{v.size}" }.join(", ") + ".\n\n"
shared_pairs = cat.call(:renamed).reject { |e| e.detail == "to nested payload" }
  .map { |e| [e.old_type.delete("[]"), e.new_type.delete("[]")] }.tally.sort_by { |_, n| -n }
out << "Most common targets of a rename to or move into a shared schema:\n\n"
shared_pairs.first(15).each { |(ot, nt), n| out << "- #{fence.call(short.call(ot))} -> #{fence.call(short.call(nt))} (#{n})\n" }
out << "\n"

out << "## Type changes (#{cat.call(:changed).size})\n\n"
out << "| old parent -> new parent | JSON key | old | new | note | example path |\n|---|---|---|---|---|---|\n"
cat.call(:changed).sort_by { |e| [e.old_parent, e.key] }.each do |e|
  out << "| #{fence.call(short.call(e.old_parent))} -> #{fence.call(short.call(e.new_parent))} | #{e.key} | #{fence.call(e.old_type)} | #{fence.call(short.call(e.new_type))} | #{e.detail} | #{e.path} |\n"
end

out << "\n## Removed in new (#{cat.call(:removed).size}), grouped by (old type -> new type)\n\n"
out << "Present in swift-slack today (a quicktype merge across upstream java-slack-sdk fixtures), absent from the matching new type. Most of these are old shared types (`SlackModels.Channel`, `User`, `Message`) paired with a slimmer upstream inner class, so the key is still available on the new shared schema but not at this position. Counts are unique keys.\n\n"
cat.call(:removed).group_by { |e| [e.old_parent, e.new_parent] }.sort_by { |pair, v| [-v.size, pair] }.each do |(old_parent, new_parent), v|
  target = old_parent.split(".").last == new_parent.split(".").last ? "" : " -> #{fence.call(short.call(new_parent))}"
  out << "- #{fence.call(short.call(old_parent))}#{target} (#{v.map(&:key).uniq.size}): #{v.map(&:key).uniq.sort.join(", ")}\n"
end

out << "\n## Added in new (#{cat.call(:added).size}), top parents\n\n"
out << "Present in the upstream java-slack-sdk class, absent from swift-slack today.\n\n"
cat.call(:added).group_by(&:new_parent).sort_by { |p, v| [-v.size, p] }.first(25).each do |parent, v|
  keys = v.map(&:key).uniq.sort
  out << "- #{fence.call(short.call(parent))} (#{v.map(&:key).uniq.size}): #{keys.first(12).join(", ")}#{keys.size > 12 ? ", ..." : ""}\n"
end

out << "\n## The five prototype methods\n\n"
FIVE.each do |name|
  resp = "Components.Schemas.#{name}"
  next unless reach[resp]

  list = reach[resp].flat_map { |pair| differ.pair_entries[pair] }.reject { |e| e.category == :unchanged }
  counts = list.map(&:category).tally
  out << "### #{name}\n\n#{counts.map { |c, n| "#{c} #{n}" }.join(", ")}\n\n"
  [[:renamed, nil], [:changed, nil], [:removed, nil], [:added, nil]].each do |c, _|
    items = list.select { |e| e.category == c }
    next if items.empty?

    shown = items.first(c == :removed || c == :added ? 25 : 40)
    out << "- #{c}: " + shown.map { |e|
      case c
      when :renamed then "#{fence.call(short.call(e.old_type))} -> #{fence.call(short.call(e.new_type))} at #{e.key}"
      when :changed then "#{e.key}: #{fence.call(e.old_type)} -> #{fence.call(short.call(e.new_type))}"
      else e.key
      end
    }.join("; ") + (items.size > shown.size ? "; ... (#{items.size} total)" : "") + "\n"
  end
  out << "\n"
end

out << <<~LIMITS
  ## Limitations

  - Static text analysis of Swift declarations, not a type-checker. Types it cannot resolve in the generated or hand-written sources are compared by the name as written.
  - Each (old type, new type) pair is compared once however many responses reach it, so counts are unique property comparisons, not occurrences along every JSON path. The example path is the first one found, breadth-first.
  - Hand-written SlackModels types carry no Remark comments: the JSON key is the `CodingKeys` entry when present, else the Swift property name.
  - oneOf unions, string enums and typealiases are leaves; they are compared by name only. Block Kit types (SlackBlockKit) are leaves on both sides.
  - `additionalProperties` is a single pseudo key `*`.
  - A renamed model type is still walked, so its own differences appear under the pair; the rename is counted on the referencing property.
  - Descendants of a removed or added property are not counted separately.
  - A map is a `[String: T]` in some hand-written old types but a struct with `additionalProperties` in swift-openapi-generator output; this shows up as a container change.
  - Only the `<Method>Response` types present in both are walked. Responses only in new (legacy `channels.*`, `groups.*`, `im.*`, `mpim.*`, other methods old main does not generate) and only in old (`oauth.v2.*`, `openid.connect.*`, `api.test`, which the Java classes name differently) are listed but not compared.
  - Compares declared types only. Whether the old types decode a payload the new types reject (or the reverse) is covered by the decode checks in REPORT.md.
LIMITS

out_path = File.join(__dir__, "reports/api-diff.md")
OptionParser.new { |o| o.on("--out PATH") { |p| out_path = p } }.parse!
File.write(out_path, out)
puts "wrote #{out_path}: #{both.size} responses, #{entries.size} comparisons (#{by_category.transform_values(&:size)})"
