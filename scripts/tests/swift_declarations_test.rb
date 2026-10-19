# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/swift_declarations'

class SwiftDeclarationsTest < Minitest::Test
  def lines(source)
    source.lines
  end

  def test_splits_header_from_declarations
    source = <<~SWIFT
      import Foundation
      import OpenAPIRuntime

      public struct A {
          var x: Int
      }

      public enum B {}
      public typealias C = Int
      public func f() {
      }
    SWIFT
    header, declarations = SwiftDeclarations.split(lines(source), indent: 0)

    assert_equal "import Foundation\nimport OpenAPIRuntime\n\n", header.join
    assert_equal %w[A B C f], declarations.map(&:name)
    assert_equal "public struct A {\n    var x: Int\n}\n", declarations[0].text
    assert_equal "public enum B {}\n", declarations[1].text
  end

  def test_leading_comments_attach_to_declaration_and_stay_out_of_header
    source = <<~SWIFT
      import Foundation

      /// Docs for A.
      /// Second line.
      public struct A {}

      // plain comment
      public struct B {}
    SWIFT
    header, declarations = SwiftDeclarations.split(lines(source), indent: 0)

    assert_equal "import Foundation\n\n", header.join
    assert_equal "/// Docs for A.\n/// Second line.\npublic struct A {}\n", declarations[0].text
    assert_equal "// plain comment\npublic struct B {}\n", declarations[1].text
  end

  def test_blank_lines_and_directives_between_declarations_are_dropped
    source = <<~SWIFT
      struct A {}

      #if canImport(X)
      struct B {}
    SWIFT
    _, declarations = SwiftDeclarations.split(lines(source), indent: 0)

    assert_equal "struct A {}\n", declarations[0].text
    assert_equal "struct B {}\n", declarations[1].text
  end

  def test_splits_members_at_an_indentation_level
    source = <<~SWIFT
      extension Client {
          /// Sends.
          public func send(
              input: Input
          ) async throws -> Output {
              return try await call()
          }
          public init(a: Int) {
              self.a = a
          }
          private static let shared = 1
          @inlinable public var y: Int { 2 }
      }
    SWIFT
    all = lines(source)
    _, outer = SwiftDeclarations.split(all, indent: 0)
    body = SwiftDeclarations.body(outer.first)
    header, members = SwiftDeclarations.split(body, indent: 4)

    assert_empty header
    assert_equal %w[send init shared y], members.map(&:name)
    assert_equal "    /// Sends.\n", members[0].lines.first
    assert_equal 6, members[0].lines.size
    assert_equal 1, members[3].lines.size
  end

  def test_name_variants
    source = <<~SWIFT
      public final class A {}
      @frozen public struct B {}
      indirect enum C {}
      protocol D {}
      extension Foo.Bar {}
      init() {}
    SWIFT
    _, declarations = SwiftDeclarations.split(lines(source), indent: 0)

    assert_equal %w[A B C D Foo.Bar init], declarations.map(&:name)
  end

  def test_braces_in_strings_and_comments_are_ignored
    source = <<~SWIFT
      struct A {
          let s = "}}}"
          let t = "esc \\" {"
          // closing } in a comment
          let u = 1 // trailing {
      }
      struct B {}
    SWIFT
    _, declarations = SwiftDeclarations.split(lines(source), indent: 0)

    assert_equal %w[A B], declarations.map(&:name)
    assert_equal 6, declarations[0].lines.size
  end

  def test_unbalanced_braces_raise
    error = assert_raises(RuntimeError) { SwiftDeclarations.split(lines("struct A {\n    var x = 1\n"), indent: 0) }

    assert_match(/unbalanced braces/, error.message)
  end

  def test_no_declarations_returns_everything_as_header
    header, declarations = SwiftDeclarations.split(lines("import X\n\n"), indent: 0)

    assert_equal "import X\n\n", header.join
    assert_empty declarations
  end

  def test_body_skips_leading_doc_comments
    _, declarations = SwiftDeclarations.split(lines("/// doc\nstruct A {\n    var x = 1\n    var y = 2\n}\n"), indent: 0)

    assert_equal ["    var x = 1\n", "    var y = 2\n"], SwiftDeclarations.body(declarations.first)
  end

  def test_depth_delta
    assert_equal 1, SwiftDeclarations.depth_delta("struct A {\n")
    assert_equal 1, SwiftDeclarations.depth_delta("func f(\n")
    assert_equal 0, SwiftDeclarations.depth_delta("// {{{\n")
    assert_equal 0, SwiftDeclarations.depth_delta("let s = \"{(\"\n")
  end
end
