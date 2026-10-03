require 'minitest/autorun'
require 'tmpdir'
require 'open3'
require 'rbconfig'
require_relative '../lib/code_generation/slackmodels_extractor'

class SlackModelsExtractorTest < Minitest::Test
  def test_new_handwritten_file_is_discovered_without_registering_its_type
    Dir.mktmpdir do |directory|
      handwritten = File.join(directory, 'SlackModels')
      FileUtils.mkdir_p(File.join(handwritten, 'Generated'))
      types = write_types(directory, %w[NewModel GeneratedModel View Block SampleResponse])
      File.write(File.join(handwritten, 'Generated', 'GeneratedModel.swift'), '// Previous generated output')

      first_output = File.join(directory, 'first')
      capture_io { SlackModelsExtractor.new(types, first_output, handwritten_models_dir: handwritten).extract }
      assert_equal %w[GeneratedModel.swift NewModel.swift], generated_files(first_output)

      source = File.join(handwritten, 'NewModel.swift')
      File.write(source, '// Handwritten implementation')
      second_output = File.join(directory, 'second')
      capture_io { SlackModelsExtractor.new(types, second_output, handwritten_models_dir: handwritten).extract }
      assert_equal ['GeneratedModel.swift'], generated_files(second_output)
      assert_equal '// Handwritten implementation', File.read(source)
    end
  end

  def test_emitted_alias_does_not_duplicate_a_handwritten_type
    Dir.mktmpdir do |directory|
      handwritten = File.join(directory, 'SlackModels')
      FileUtils.mkdir_p(handwritten)
      File.write(File.join(handwritten, 'TabData.swift'), '// Handwritten aliased model')
      types = write_types(directory, %w[Data OtherModel])
      output = File.join(directory, 'output')

      capture_io { SlackModelsExtractor.new(types, output, handwritten_models_dir: handwritten).extract }
      assert_equal ['OtherModel.swift'], generated_files(output)
    end
  end

  def test_standalone_extractor_uses_the_shared_policy_from_another_directory
    Dir.mktmpdir do |directory|
      types = write_types(directory, %w[RecordChannel View Block OtherModel SampleResponse])
      output = File.join(directory, 'output')
      script = File.expand_path('../extract_slackmodels.rb', __dir__)
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, script, types, output, chdir: directory)

      assert status.success?, "#{stdout}\n#{stderr}"
      assert_equal ['OtherModel.swift'], generated_files(output)
    end
  end

  private

  def generated_files(directory)
    Dir.glob(File.join(directory, '*.swift')).map { File.basename(_1) }.sort
  end

  def write_types(directory, names)
    schemas = names.map do |name|
      <<~SWIFT
        /// - Remark: Generated from `#/components/schemas/#{name}`.
        public struct #{name}: Codable {
        }
      SWIFT
    end.join
    path = File.join(directory, 'Types.swift')
    File.write(path, "public enum Components {\n    public enum Schemas {\n#{schemas}\n    }\n}\n")
    path
  end
end
