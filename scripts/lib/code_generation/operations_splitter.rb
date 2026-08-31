require 'fileutils'
require_relative '../output'

# Handles splitting of Operations.swift by operation groups
class OperationsSplitter
  def initialize(output_directory)
    @output_directory = output_directory
  end

  # Splits Operations.swift into group-specific files with conditional compilation
  def split_operations_file
    operations_file = File.join(@output_directory, 'Operations.swift')
    return unless File.exist?(operations_file)

    Output.step "Splitting Operations.swift by operation groups"
    content = File.read(operations_file)

    # Parse operation enums using more sophisticated approach
    operation_groups = parse_operations_by_groups(content)

    # Create Operations subdirectory
    operations_dir = File.join(@output_directory, 'Operations')
    FileUtils.mkdir_p(operations_dir)

    # Write group files
    operation_groups.each do |group, content_lines|
      filename = "Operations+#{GroupNameFormatter.capitalize_group_name(group)}.swift"
      filepath = File.join(operations_dir, filename)

      File.write(filepath, content_lines)
      Output.created "Operations/#{filename}", content_lines.lines.size
    end

    # Remove original Operations.swift
    File.delete(operations_file)
    Output.info "Removed original Operations.swift"
  end

  private

  # Parses Operations.swift content and groups operations by API groups
  def parse_operations_by_groups(content)
    lines = content.lines
    groups = Hash.new { |h, k| h[k] = [] }

    # Find the header (everything up to Operations enum)
    operations_start = lines.find_index { |line| line.strip.match(/^public enum Operations/) }
    return {} unless operations_start

    header = lines[0...operations_start].join

    # Parse each operation enum with proper brace counting
    current_operation = nil
    operation_lines = []
    brace_depth = 0
    in_operation = false

    lines[(operations_start + 1)..-1].each do |line|
      stripped = line.strip

      # Look for operation enum declarations
      if match = stripped.match(/^public enum (\w+):/)
        # Save previous operation
        if current_operation && !operation_lines.empty?
          group = OperationGroupExtractor.extract_operation_group_name(current_operation)
          groups[group] << operation_lines.join
        end

        # Start new operation
        current_operation = $1
        operation_lines = [line]
        brace_depth = 1  # Start counting from the opening brace
        in_operation = true
        next
      end

      if in_operation && current_operation
        operation_lines << line
        brace_depth += line.count('{') - line.count('}')

        # End of operation enum
        if brace_depth == 0
          group = OperationGroupExtractor.extract_operation_group_name(current_operation)
          groups[group] << operation_lines.join
          current_operation = nil
          operation_lines = []
          in_operation = false
        end
      end
    end

    # Handle final operation
    if current_operation && !operation_lines.empty?
      group = OperationGroupExtractor.extract_operation_group_name(current_operation)
      groups[group] << operation_lines.join
    end

    # Generate complete file content for each group
    result = {}
    groups.each do |group, operations|
      # Adjust indentation - remove 4 spaces from each line since we're moving from nested to extension
      adjusted_operations = operations.map { |operation|
        operation.lines.map { |line|
          # Remove 4 spaces of indentation if the line has enough leading spaces
          if line.start_with?('        ')  # 8 spaces originally
            '    ' + line[8..-1]  # Keep 4 spaces
          else
            line
          end
        }.join
      }

      trait = "WebAPI_#{GroupNameFormatter.capitalize_group_name(group)}"
      content = header + "\n#if #{trait}\nextension Operations {\n" +
               adjusted_operations.join + "}\n#endif\n"

      # Apply transformations to operations content
      content = CodeTransformer.transform_operations_content(content)

      result[group] = content
    end

    result
  end
end
