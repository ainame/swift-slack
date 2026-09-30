require 'etc'
require 'json'
require 'open3'
require 'shellwords'

DEFAULT_CONCURRENCY = [Etc.nprocessors, 8].min

def generation_concurrency
  concurrency = Integer(ENV.fetch('GENERATION_JOBS', DEFAULT_CONCURRENCY.to_s), 10)
  raise ArgumentError, 'GENERATION_JOBS must be at least 1' if concurrency < 1

  concurrency
end

def process_in_queue(items, &block)
  queue = Queue.new
  items.each { |item| queue.push(item) }
  queue.close

  worker_count = [generation_concurrency, items.length].min
  threads = worker_count.times.map do
    Thread.new do
      while (item = queue.pop)
        block.call(item)
      end
    end
  end

  threads.each(&:join)
end

def generate_json_schema(input_path, output_path, model_name)
  quicktype = ENV.fetch(
    'QUICKTYPE_BIN',
    File.expand_path('../../node_modules/.bin/quicktype', __dir__)
  )
  unless File.executable?(quicktype)
    raise "quicktype is not installed at #{quicktype}. Run `npm ci` before generation."
  end

  command = [
    quicktype,
    '--lang', 'schema',
    '--alphabetize-properties',
    '--all-properties-optional',
    '--top-level', model_name,
    input_path,
  ]
  puts "Generating schema: $ #{Shellwords.join(command)}"
  stdout, stderr, status = Open3.capture3(*command)
  unless status.success?
    raise "quicktype failed for #{input_path} (exit #{status.exitstatus}):\n#{stderr.strip}"
  end

  begin
    parsed = JSON.parse(stdout)
  rescue JSON::ParserError => error
    details = stderr.strip.empty? ? stdout[0, 1_000] : stderr.strip
    raise "quicktype emitted invalid JSON for #{input_path}: #{error.message}\n#{details}"
  end

  temporary_path = "#{output_path}.tmp-#{Process.pid}-#{Thread.current.object_id}"
  File.write(temporary_path, stdout)
  File.rename(temporary_path, output_path)
  parsed
ensure
  File.delete(temporary_path) if defined?(temporary_path) && temporary_path && File.exist?(temporary_path)
end

# extension to string
class String
  def camelize(separator: '_')
    gsub(/#{separator}([a-z0-9])/) { Regexp.last_match(1).upcase }
  end
end
