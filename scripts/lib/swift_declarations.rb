# frozen_string_literal: true

# Splits Swift source emitted by Apple's swift-openapi-generator into declarations.
#
# The generator's output is consistently indented with four spaces per level, so the members of a type are
# the declarations that start at one indentation level. A declaration owns the comment lines directly before
# it and ends where its braces and parentheses balance. Brackets inside comments and string literals are
# ignored.
module SwiftDeclarations
  # One declaration: the declared name and its source lines, leading comments included.
  Declaration = Struct.new(:name, :lines) do
    def text
      lines.join
    end
  end

  NAME_PATTERN = /\A(?:@[\w()]+\s+)*(?:(?:public|internal|private|fileprivate|package|static|indirect|final)\s+)*
                  (?:(?:struct|enum|class|protocol|extension|typealias|func|var|let)\s+([\w.]+)|(init)\b)/x

  module_function

  def comment?(line)
    line.lstrip.start_with?('//')
  end

  def indentation(line)
    line[/\A */].size
  end

  # Net change of brace plus parenthesis depth on a line, ignoring comments and string literals.
  # Parentheses keep a multi-line signature such as `func send(\n    input: Input\n) async throws {` open.
  def depth_delta(line)
    return 0 if comment?(line)

    code = line.gsub(/"(?:\\.|[^"\\])*"/, '""').sub(%r{//.*}, '')
    code.count('{(') - code.count('})')
  end

  # Splits `lines` into [header, declarations] for the declarations starting at `indent` spaces.
  # The header is everything before the first declaration except that declaration's leading comments
  # (for a whole file: the imports). Lines between later declarations that are not comments, such as
  # blank lines and compiler directives, are dropped.
  def split(lines, indent:)
    header = nil
    declarations = []
    pending = []
    current = nil
    depth = 0

    lines.each do |line|
      if current
        current << line
        depth += depth_delta(line)
      elsif declaration_start?(line, indent)
        leading = pending.reverse.take_while { |pending_line| comment?(pending_line) }.reverse
        header ||= pending.first(pending.size - leading.size)
        current = leading + [line]
        pending = []
        depth = depth_delta(line)
      else
        pending << line
        next
      end
      next unless depth.zero?

      declarations << Declaration.new(declared_name(current), current)
      current = nil
    end
    raise "unbalanced braces after #{current.first(3).join.inspect}" if current

    [header || pending, declarations]
  end

  def declaration_start?(line, indent)
    indentation(line) == indent && !comment?(line) && line.strip.match?(NAME_PATTERN)
  end

  def declared_name(lines)
    signature = lines.find { |line| !comment?(line) }.strip
    match = signature.match(NAME_PATTERN) or raise "cannot read the declared name of #{signature.inspect}"
    match[1] || match[2]
  end

  # The lines between the opening line and the closing brace of a declaration.
  def body(declaration)
    lines = declaration.lines
    open_index = lines.index { |line| !comment?(line) }
    lines[(open_index + 1)...-1]
  end
end
