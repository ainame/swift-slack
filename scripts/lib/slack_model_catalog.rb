# Handwritten SlackModels use one top-level type per file. Generated models live
# in the Generated subdirectory and must not count as handwritten overrides.
module SlackModelCatalog
  DIRECTORY = File.expand_path('../../Sources/SlackModels', __dir__).freeze

  SCHEMA_ALIASES = { 'Data' => 'TabData' }.freeze

  def self.emitted_name(schema_name)
    SCHEMA_ALIASES.fetch(schema_name, schema_name)
  end

  def self.handwritten_types(directory = DIRECTORY)
    Dir.glob(File.join(directory, '*.swift')).map { File.basename(_1, '.swift') }.sort
  end
end
