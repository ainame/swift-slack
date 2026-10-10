# frozen_string_literal: true

require 'set'
require_relative 'java_openapi/class_index'
require_relative 'java_openapi/gson_adapters'
require_relative 'java_openapi/schema_builder'
require_relative 'java_openapi/type_overrides'

# Web API response and event schemas derived from the upstream java-slack-sdk Java classes.
#
#   upstream java-slack-sdk .java -> tree-sitter syntax tree -> ClassIndex -> SchemaBuilder -> OpenAPI schemas
module JavaOpenAPI
  MODEL_ROOT = 'slack-api-model/src/main/java'
  CLIENT_ROOT = 'slack-api-client/src/main/java'
  RESPONSE_PACKAGE = SchemaBuilder::RESPONSE_PACKAGE
  EVENT_PACKAGE = 'com.slack.api.model.event'

  # Response classes whose names do not follow `<Method>Response` (`oauth.v2.access` => OauthV2AccessResponse).
  RESPONSE_CLASSES = {
    'oauth.access' => 'OAuthAccessResponse',
    'oauth.token' => 'OAuthTokenResponse',
    'oauth.v2.access' => 'OAuthV2AccessResponse',
    'oauth.v2.exchange' => 'OAuthV2ExchangeResponse',
    'openid.connect.token' => 'OpenIDConnectTokenResponse',
    'openid.connect.userInfo' => 'OpenIDConnectUserInfoResponse',
    'rtm.connect' => 'RTMConnectResponse',
    'rtm.start' => 'RTMStartResponse',
  }.freeze

  # Swift schema names that differ from `<Method>Response`, kept for source compatibility.
  RESPONSE_SCHEMA_NAMES = { 'api.test' => 'APITestResponse' }.freeze

  module_function

  # Parses the model, event and response classes of the java-slack-sdk checkout at `sdk_dir`.
  def load_index(sdk_dir)
    ClassIndex.new
              .add_tree(File.join(sdk_dir, MODEL_ROOT, 'com/slack/api/model'))
              .add_tree(File.join(sdk_dir, CLIENT_ROOT, 'com/slack/api/methods/response'))
  end

  # `chat.postMessage` => "ChatPostMessage"
  def pascal_case(method)
    method.split('.').map { |part| part[0].upcase + part[1..] }.join
  end

  # The schema name of a method's response, e.g. ChatPostMessageResponse.
  def response_schema_name(method)
    RESPONSE_SCHEMA_NAMES.fetch(method) { "#{pascal_case(method)}Response" }
  end

  # The Java response class of `method`. Raises when there is none or the name is ambiguous.
  # When several packages declare the name (upstream has a stray channels.UsersLookupByEmailResponse),
  # the one in the package of the method's group wins.
  def response_class(index, method)
    name = RESPONSE_CLASSES.fetch(method) { "#{pascal_case(method)}Response" }
    candidates = index.classes_named(name).select { |java_class| java_class.fqn.start_with?("#{RESPONSE_PACKAGE}.") }
    raise "no java-slack-sdk response class #{name} for #{method}" if candidates.empty?

    group_package = "#{RESPONSE_PACKAGE}.#{method.split('.').first.downcase}"
    in_group = candidates.select { |java_class| java_class.file.package == group_package }
    candidates = in_group if in_group.size == 1
    raise "several java-slack-sdk response classes named #{name}: #{candidates.map(&:fqn).join(', ')}" if candidates.size > 1

    candidates.first
  end

  # The Java event class for an event name such as `IMClose` (the fixture IMClosePayload.json).
  # Java spells acronyms differently (ImCloseEvent), so the match ignores case.
  def event_class(index, event_name)
    wanted = "#{event_name}Event".downcase
    candidates = index.package_classes(EVENT_PACKAGE).values.select { |java_class| java_class.name.downcase == wanted }
    raise "no java-slack-sdk event class for #{event_name}" if candidates.empty?

    candidates.first
  end

  # Public type names declared in Swift sources under `directory` (SlackBlockKit).
  def swift_public_types(directory)
    Dir.glob('**/*.swift', base: directory).sort.each_with_object(Set.new) do |relative, names|
      File.read(File.join(directory, relative), encoding: 'UTF-8').scan(/^public (?:struct|enum|class|protocol) (\w+)/) do |(name)|
        names << name
      end
    end
  end
end
