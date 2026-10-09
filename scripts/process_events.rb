#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require_relative 'lib/content_transformer'
require_relative 'lib/output'

# Repository sources are UTF-8; do not depend on the caller's locale.
Encoding.default_external = Encoding::UTF_8

# Handles transformation of generated Events code to extract Event structs
# and transform them into individual SlackEvent conforming types
class EventsProcessor
  def self.run(input_file = nil, output_directory = nil)
    new(input_file, output_directory).run
  end

  def initialize(input_file = nil, output_directory = nil)
    @input_file = input_file || File.join(__dir__, '..', '.tmp', 'Events', 'Types.swift')
    @output_directory = output_directory || File.join(__dir__, '..', 'Sources', 'SlackApp', 'Events', 'Generated')
  end

  # Main processing method that extracts and transforms Event structs
  def run
    unless File.exist?(@input_file)
      Output.info "Error: Events Types.swift not found at #{@input_file}"
      exit 1
    end

    Output.step "Processing Events Types.swift"
    Output.info "Input file: #{@input_file}"
    Output.info "Output directory: #{@output_directory}"

    # Create output directory
    FileUtils.mkdir_p(@output_directory)

    # Parse and extract Event structs
    content = File.read(@input_file)
    event_structs = extract_event_structs(content)

    # Generate individual event files
    event_structs.each do |event_name, event_content|
      generate_event_file(event_name, event_content)
    end

    # Generate polymorphic Event enum
    generate_event_type_enum(event_structs.keys)

    Output.summary "Processing complete! Generated #{event_structs.size} event files + Event.swift:",
                   event_structs.keys.map { |name| "#{name}.swift" } + ["Event.swift"]
  end

  private

  # Dynamically determines which types have been moved to SlackModels
  def get_slackmodels_types
    @slackmodels_types ||= begin
      types = []

      # Check both SlackModels root directory and Generated subdirectory
      slackmodels_root = File.join(__dir__, '..', 'Sources', 'SlackModels')
      slackmodels_generated = File.join(slackmodels_root, 'Generated')

      # Get manually created models from SlackModels root
      if Dir.exist?(slackmodels_root)
        Dir.glob(File.join(slackmodels_root, '*.swift')).each do |file|
          types << File.basename(file, '.swift')
        end
      end

      # Get generated models from SlackModels/Generated
      if Dir.exist?(slackmodels_generated)
        Dir.glob(File.join(slackmodels_generated, '*.swift')).each do |file|
          types << File.basename(file, '.swift')
        end
      end

      types.sort.uniq
    end
  end

  # Extracts all Event structs from the Components.Schemas enum
  def extract_event_structs(content)
    lines = content.lines
    event_structs = {}

    # Find the start of Components.Schemas
    schemas_start = lines.find_index { |line| line.strip.match(/^public enum Schemas/) }
    return {} unless schemas_start

    i = schemas_start + 1
    while i < lines.length
      line = lines[i]
      stripped = line.strip

      # Look for Event struct comment (not property-level comments)
      if match = stripped.match(/\/\/\/ - Remark: Generated from `#\/components\/schemas\/(\w+Event)`\.$/)
        event_name = $1
        event_lines = []

        # Collect all lines until we hit the next struct or enum
        j = i
        while j < lines.length
          current_line = lines[j]
          current_stripped = current_line.strip

          # Stop if we hit another struct/enum declaration (not property comments)
          if j > i && current_stripped.match(/^\/\/\/ - Remark: Generated from `#\/components\/schemas\/(\w+)`\.$/)
            break
          end

          event_lines << current_line
          j += 1
        end


        if !event_lines.empty?
          event_structs[event_name] = event_lines.join
        end

        i = j  # Continue from where we left off
      else
        i += 1
      end
    end

    event_structs
  end

  # Generates an individual event file with proper transformations
  def generate_event_file(event_name, event_content)
    # Transform the event content
    transformed_content = transform_event_content(event_content, event_name)


    # Check if we need imports
    needs_slackblockkit_import = transformed_content.include?('Block') ||
                                transformed_content.include?('View')
    needs_slackmodels_import = transformed_content.include?('SlackModels.')

    # Generate the complete file content
    file_content = generate_file_content(event_name, transformed_content, needs_slackblockkit_import, needs_slackmodels_import)

    # Write the file
    filename = "#{event_name}.swift"
    filepath = File.join(@output_directory, filename)
    File.write(filepath, file_content)
    Output.created filename
  end

  # Generates the polymorphic Event enum for handling all event types
  def generate_event_type_enum(event_names)
    # Sort event names for consistent output
    sorted_events = event_names.sort

    # Separate message subtypes from regular events
    message_subtypes = []
    regular_events = []
    
    sorted_events.each do |event_name|
      # Check if this is a message subtype event
      # MessageEvent itself is the base message type (no subtype)
      # Events like MessageChangedEvent, MessageBotEvent etc are subtypes
      if event_name.start_with?('Message') && event_name != 'MessageEvent'
        message_subtypes << event_name
      else
        regular_events << event_name
      end
    end

    # Generate enum cases (all events get enum cases)
    enum_cases = sorted_events.map do |event_name|
      case_name = camel_case_to_lower_camel_case(event_name.gsub(/Event$/, ''))
      "    case #{case_name}(#{event_name})"
    end

    # Generate switch cases for regular events (non-message subtypes)
    # Exclude MessageEvent from regular switch cases if we have message subtypes to handle
    events_for_switch = regular_events.dup
    if !message_subtypes.empty?
      events_for_switch.delete('MessageEvent')
    end
    
    switch_cases = events_for_switch.map do |event_name|
      case_name = camel_case_to_lower_camel_case(event_name.gsub(/Event$/, ''))
      type_value = generate_slack_event_type(event_name)
      "        case \"#{type_value}\":\n            self = .#{case_name}(try #{event_name}(from: decoder))"
    end

    # Add special case for "message" type that checks subtype
    if regular_events.include?('MessageEvent') || !message_subtypes.empty?
      message_subtype_cases = generate_message_subtype_cases(message_subtypes)
      switch_cases << generate_message_type_case(message_subtype_cases)
    end

    # Generate switch cases for payload computed property
    payload_cases = sorted_events.map do |event_name|
      case_name = camel_case_to_lower_camel_case(event_name.gsub(/Event$/, ''))
      "        case .#{case_name}(let event):\n            return event"
    end

    file_content = <<~SWIFT
#if Events
import Foundation

/// Polymorphic event type that can decode any Slack event based on the type field
public enum Event: Decodable, Hashable, Sendable {
#{enum_cases.join("\n")}
    case unsupported(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
#{switch_cases.join("\n")}
        default:
            self = .unsupported(type)
        }
    }

    /// Returns the contained event as a SlackEvent
    public var payload: (any SlackEvent)? {
        switch self {
#{payload_cases.join("\n")}
        case .unsupported:
            return nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }
    
    private enum MessageSubtypeCodingKeys: String, CodingKey {
        case subtype
    }
}
#endif
    SWIFT

    # Write the Event.swift file
    filename = "Event.swift"
    filepath = File.join(@output_directory, filename)
    File.write(filepath, file_content)
    Output.created filename
  end

  # Generates the message subtype cases for the special "message" type handling
  def generate_message_subtype_cases(message_subtypes)
    message_subtypes.map do |event_name|
      case_name = camel_case_to_lower_camel_case(event_name.gsub(/Event$/, ''))
      subtype_value = generate_message_subtype_value(event_name)
      "            case \"#{subtype_value}\":\n                self = .#{case_name}(try #{event_name}(from: decoder))"
    end
  end

  # Generates the special case statement for "message" type that checks subtype
  def generate_message_type_case(subtype_cases)
    <<~CASE.chomp
        case "message":
            // Message events require checking the subtype field
            let subtypeContainer = try decoder.container(keyedBy: MessageSubtypeCodingKeys.self)
            let subtype = try subtypeContainer.decodeIfPresent(String.self, forKey: .subtype)
            
            switch subtype {
#{subtype_cases.join("\n")}
            case nil:
                // No subtype - regular message
                self = .message(try MessageEvent(from: decoder))
            case .some(let unknownSubtype):
                // Unknown subtype - mark as unsupported
                self = .unsupported("message - \\(unknownSubtype)")
            }
    CASE
  end

  # Generates the Slack message subtype value from the event class name
  def generate_message_subtype_value(event_name)
    # Remove 'Event' suffix and 'Message' prefix
    base_name = event_name.gsub(/Event$/, '').gsub(/^Message/, '')
    
    # Handle special cases
    case base_name
    when 'Bot'
      'bot_message'
    when 'Changed'
      'message_changed'
    when 'Deleted'
      'message_deleted'
    when 'Replied'
      'message_replied'
    when 'ThreadBroadcast'
      'thread_broadcast'
    when 'Me'
      'me_message'
    when 'FileShare'
      'file_share'
    when 'EkmAccessDenied'
      'ekm_access_denied'
    when 'GroupTopic'
      'group_topic'
    else
      # For channel-related subtypes like MessageChannelArchive -> channel_archive
      if base_name.start_with?('Channel')
        base_name = base_name.gsub(/^Channel/, '')
        case base_name
        when 'Archive'
          'channel_archive'
        when 'Join'
          'channel_join'
        when 'Leave'
          'channel_leave'
        when 'Name'
          'channel_name'
        when 'Purpose'
          'channel_purpose'
        when 'Topic'
          'channel_topic'
        when 'Unarchive'
          'channel_unarchive'
        when 'PostingPermissions'
          'channel_posting_permissions'
        else
          # Default: convert to snake_case
          base_name.gsub(/([A-Z])/) { "_#{$1.downcase}" }.sub(/^_/, '').downcase
        end
      else
        # Default: convert to snake_case
        base_name.gsub(/([A-Z])/) { "_#{$1.downcase}" }.sub(/^_/, '').downcase
      end
    end
  end

  # Converts CamelCase to lowerCamelCase for enum case names
  def camel_case_to_lower_camel_case(str)
    # Handle special cases
    str = str.gsub(/ID/, 'Id')  # ChannelIDChanged -> ChannelIdChanged
    str = str.gsub(/IM/, 'Im')  # IMClose -> ImClose
    
    # Convert to snake_case first
    snake_case = str.gsub(/([A-Z])/) { "_#{$1.downcase}" }.sub(/^_/, '').downcase
    
    # Convert snake_case to lowerCamelCase
    parts = snake_case.split('_')
    parts.first + parts[1..-1].map(&:capitalize).join
  end

  # Generates the Slack event type string from the event class name
  def generate_slack_event_type(event_name)
    # Remove 'Event' suffix and convert to snake_case
    base_name = event_name.gsub(/Event$/, '')
    
    # Handle special cases for Slack's naming conventions
    base_name = base_name.gsub(/ID/, 'Id')  # ChannelIDChanged -> ChannelIdChanged
    base_name = base_name.gsub(/IM/, 'Im')  # IMClose -> ImClose
    
    # Convert to snake_case for Slack event type format
    base_name.gsub(/([A-Z])/) { "_#{$1.downcase}" }.sub(/^_/, '').downcase
  end

  # Transforms event struct content according to requirements
  def transform_event_content(content, event_name)
    lines = content.lines
    transformed_lines = []
    skip_until_end = false
    skip_brace_depth = 0
    struct_brace_depth = 0
    in_struct = false
    in_coding_keys = false

    lines.each do |line|
      stripped = line.strip

      # Detect start of struct
      if line.match(/(\s*)public struct #{Regexp.escape(event_name)}:/)
        in_struct = true
        struct_brace_depth = 1  # Opening brace of struct
        # Change struct declaration to conform to SlackEvent
        line = line.gsub(/:.*$/, ': SlackEvent {')
        transformed_lines << line
        next
      end

      # Only process lines inside the struct
      next unless in_struct

      # Track overall struct brace depth
      struct_brace_depth += line.count('{') - line.count('}')
      
      # Check if we've reached the end of the struct
      if struct_brace_depth == 0
        transformed_lines << "}\n"
        break
      end

      # Handle CodingKeys enum - KEEP IT
      if stripped.match(/^public enum CodingKeys:/)
        in_coding_keys = true
        transformed_lines << line
        next
      end

      # Handle CodingKeys content
      if in_coding_keys
        transformed_lines << line
        
        # Check if we're at the end of CodingKeys enum
        if stripped == '}' && line.strip == '}'
          in_coding_keys = false
        end
        next
      end

      # Skip custom init and decode methods
      if stripped.start_with?('public init(') ||
         stripped.start_with?('/// Creates a new') ||
         stripped.start_with?('public init(from decoder:') ||
         stripped.start_with?('public func encode(')
        skip_until_end = true
        skip_brace_depth = line.count('{') - line.count('}')
        next
      end

      if skip_until_end
        skip_brace_depth += line.count('{') - line.count('}')
        if skip_brace_depth <= 0
          skip_until_end = false
        end
        next
      end

      # Skip parameter documentation comments for init
      next if stripped.match(/^\/\/\/ - Parameters:/) ||
              stripped.match(/^\/\/\/ +- \w+:/)

      # Apply content transformations
      line = ContentTransformer.transform_type_properties(line)
      line = ContentTransformer.transform_blockkit_references(line)

      # Replace Components.Schemas.XXX with SlackModels.XXX only for types moved to SlackModels
      if line.match(/\bComponents\.Schemas\.(?!View\b|Block\b)\w+\b/)
        line = line.gsub(/\bComponents\.Schemas\.(\w+)\b/) do |match|
          type_name = $1
          # Dynamically determine which types are in SlackModels
          slackmodels_types = get_slackmodels_types

          if slackmodels_types.include?(type_name)
            "SlackModels.#{type_name}"
          else
            match  # Keep original if not moved to SlackModels
          end
        end
      end

      # Keep property declarations, remark comments, and empty lines
      if stripped.start_with?('/// - Remark:') || stripped.start_with?('public var') || stripped.empty?
        transformed_lines << line
      end
    end

    transformed_lines.join
  end

  # Generates the complete file content with proper imports and compilation directives
  def generate_file_content(event_name, transformed_content, needs_slackblockkit_import, needs_slackmodels_import)
    imports = ["import Foundation"]

    if needs_slackmodels_import
      imports << "import SlackModels"
    end

    if needs_slackblockkit_import
      imports << "#if canImport(SlackBlockKit)"
      imports << "import SlackBlockKit"
      imports << "#endif"
    end

    <<~SWIFT
      #if Events
      #{imports.join("\n")}

      #{transformed_content.strip}
      #endif
    SWIFT
  end
end

if __FILE__ == $0
  if ARGV.empty?
    EventsProcessor.run
  elsif ARGV.length == 1
    # Single argument can be input file or output directory
    arg = ARGV[0]
    if File.file?(arg)
      EventsProcessor.run(arg, nil)
    elsif Dir.exist?(arg) || arg.end_with?('/')
      EventsProcessor.run(nil, arg)
    else
      puts "Error: '#{arg}' is not a valid file or directory"
      exit 1
    end
  else
    # Two arguments: input file and output directory
    input_file = ARGV[0]
    output_directory = ARGV[1]

    unless File.exist?(input_file)
      puts "Error: Input file '#{input_file}' does not exist"
      exit 1
    end

    # Create output directory if it doesn't exist
    FileUtils.mkdir_p(output_directory)

    EventsProcessor.run(input_file, output_directory)
  end
end
