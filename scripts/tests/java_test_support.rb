# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

Encoding.default_external = Encoding::UTF_8

# Writes small Java sources into a temporary directory for the java_openapi tests.
module JavaTestSupport
  def java_dir
    @java_dir ||= Dir.mktmpdir('java-openapi-test')
  end

  def teardown
    FileUtils.remove_entry(@java_dir) if @java_dir
    super
  end

  # write_java('com/example/Foo.java', 'package com.example; ...') => path
  def write_java(relative, source)
    path = File.join(java_dir, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    path
  end

  def parse_java(source, name: 'Test.java')
    JavaSource::FileParser.new(write_java(name, source)).parse
  end

  def build_index
    ClassIndex.new.add_tree(java_dir)
  end
end
