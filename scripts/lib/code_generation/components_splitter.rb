require 'fileutils'
require_relative '../output'

# Handles splitting of Components.swift by schema groups
class ComponentsSplitter
  def initialize(output_directory)
    @output_directory = output_directory
  end

  # Splits Components.swift into group-specific files with conditional compilation
  def split_components_file
    components_file = File.join(@output_directory, 'Components.swift')
    return unless File.exist?(components_file)

    Output.step "Splitting Components.swift by schema groups"
    content = File.read(components_file)

    # Parse component schemas using more sophisticated approach
    result = parse_components_by_schemas(content)
    schema_groups = result[:groups]
    header = result[:header]

    # Create Components subdirectory
    components_dir = File.join(@output_directory, 'Components')
    FileUtils.mkdir_p(components_dir)

    # Write group files
    schema_groups.each do |group, content_lines|
      if group == 'Common'
        # Split Common schemas into individual model files
        models_dir = File.join(File.dirname(@output_directory), '..', '..', 'SlackModels', 'Generated')
        CommonModelsSplitter.new(models_dir).split_common_schemas(content_lines)

        # Create empty Components+Base.swift with just the basic structure
        base_content = generate_base_components_content(header)
        base_filename = "Components+Base.swift"
        base_filepath = File.join(components_dir, base_filename)
        File.write(base_filepath, base_content)
        Output.created "Components/#{base_filename} (basic structure)"
      else
        filename = "Components+#{GroupNameFormatter.capitalize_group_name(group)}.swift"
        filepath = File.join(components_dir, filename)
        File.write(filepath, content_lines)
        Output.created "Components/#{filename}", content_lines.lines.size
      end
    end

    # Remove original Components.swift
    File.delete(components_file)
    Output.info "Removed original Components.swift"
  end

  private

  # Generates the base Components structure
  def generate_base_components_content(header)
    <<~SWIFT
#{header}/// Types generated from the components section of the OpenAPI document.
public enum Components {
    public enum Schemas {
    }
}
    SWIFT
  end

  # Parses Components.swift content and groups schemas by API groups
  def parse_components_by_schemas(content)
    lines = content.lines
    groups = Hash.new { |h, k| h[k] = [] }

    # Find the header (everything up to Components enum)
    components_start = lines.find_index { |line| line.strip.match(/^public enum Components/) }
    schemas_start = lines.find_index { |line| line.strip.match(/^public enum Schemas/) }
    return { groups: {}, header: '' } unless components_start && schemas_start

    header = lines[0...components_start].join

    # Parse each schema struct
    current_schema = nil
    schema_lines = []
    brace_depth = 0
    in_schema = false

    lines[(schemas_start + 1)..-1].each do |line|
      stripped = line.strip

      # Look for schema struct declarations
      if match = stripped.match(/\/\/\/ - Remark: Generated from `#\/components\/schemas\/(\w+)/)
        # Save previous schema
        if current_schema && !schema_lines.empty?
          group = SchemaGroupDeterminer.determine_schema_group(current_schema)
          groups[group] << schema_lines.join
        end

        # Start new schema
        current_schema = $1
        schema_lines = [line]
        in_schema = true
        next
      elsif stripped.match(/^public struct (\w+):/) && in_schema
        schema_lines << line
        brace_depth = 1  # Start counting from the opening brace
        next
      end

      if in_schema && current_schema
        schema_lines << line
        brace_depth += line.count('{') - line.count('}')

        # End of schema structure
        if brace_depth == 0
          group = SchemaGroupDeterminer.determine_schema_group(current_schema)
          groups[group] << schema_lines.join
          current_schema = nil
          schema_lines = []
          in_schema = false
        end
      end
    end

    # Handle final schema
    if current_schema && !schema_lines.empty?
      group = SchemaGroupDeterminer.determine_schema_group(current_schema)
      groups[group] << schema_lines.join
    end

    # Generate complete file content for each group
    result = {}
    groups.each do |group, schemas|
      # Adjust indentation - remove 4 spaces from each line since we're moving from nested to extension
      adjusted_schemas = schemas.map { |schema|
        schema.lines.map { |line|
          # Remove 4 spaces of indentation if the line has enough leading spaces
          if line.start_with?('        ')  # 8 spaces originally
            '    ' + line[8..-1]  # Keep 4 spaces
          else
            line
          end
        }.join
      }

      if group == 'Common'
        content = header + "\nextension Components.Schemas {\n" + adjusted_schemas.join + "}\n"
      else
        trait = "WebAPI_#{GroupNameFormatter.capitalize_group_name(group)}"
        content = header + "\n#if #{trait}\nextension Components.Schemas {\n" +
                 adjusted_schemas.join + "}\n#endif\n"
      end

      # Apply transformations to remove CodingKeys and fix _type -> type
      content = CodeTransformer.transform_components_content(content)

      result[group] = content
    end

    { groups: result, header: header }
  end
end
