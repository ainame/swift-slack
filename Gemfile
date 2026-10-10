source "https://rubygems.org"

# Ruby 4.0.7 bundles json 2.18.0, whose generator has garbage-collection bugs that intermittently break `to_json`
# on Linux. They're fixed in 2.18.1 and 2.19.1.
gem "json", "~> 3.0", ">= 3.0.2"
gem "minitest", "~> 6.0"

# Prototypes/JavaOpenAPI parses java-slack-sdk sources with tree-sitter (grammar: vendor/tree-sitter-java).
gem "ruby_tree_sitter", "~> 2.1"
