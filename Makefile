generate:
	./scripts/generate_all.sh

clean:
	mkdir -p ./.tmp
	rm -rf ./.tmp/*
	find Sources -type d -name Generated -exec rm -rf {} +
	@echo "Resetting submodules to clean state..."
	@if [ -e "vendor/java-slack-sdk/.git" ]; then \
		cd vendor/java-slack-sdk && git reset --hard HEAD && git clean -fd; \
	fi
	@if [ -e "vendor/slack-api-ref/.git" ]; then \
		cd vendor/slack-api-ref && git reset --hard HEAD && git clean -fd; \
	fi
	git submodule update --init --recursive
	@echo "Clean complete"

SWIFTFORMAT = swift package --package-path Tools plugin --allow-writing-to-directory "$(CURDIR)" swiftformat --

format:
	$(SWIFTFORMAT) "$(CURDIR)/Sources" "$(CURDIR)/DemoApps/Examples" "$(CURDIR)/Tests"

format-generated:
	$(SWIFTFORMAT) "$(CURDIR)/Sources/SlackClient/WebAPI/Generated" "$(CURDIR)/Sources/SlackApp/Events/Generated" "$(CURDIR)/Tests/SlackClientTests/Generated"

# Decodes every generated method's and event's upstream java-slack-sdk fixture with the generated types and
# checks the fixtures against the generated schemas (scripts/check_fixtures.rb, scan_fixture_mismatches.rb).
check-fixtures: tree-sitter-java
	bundle exec ruby scripts/generate_webapi.rb > /dev/null
	bundle exec ruby scripts/scan_fixture_mismatches.rb
	bundle exec ruby scripts/check_fixtures.rb

test-scripts: tree-sitter-java
	bundle exec ruby -I scripts/tests -e 'Dir["scripts/tests/*_test.rb"].sort.each { require File.expand_path(_1) }'

update:
	@echo "Initializing and updating git submodules..."
	@if [ ! -f ".gitmodules" ]; then \
		echo "No .gitmodules file found. Setting up submodules..."; \
		git submodule add https://github.com/slackapi/java-slack-sdk.git vendor/java-slack-sdk || true; \
		git submodule add https://github.com/slack-ruby/slack-api-ref.git vendor/slack-api-ref || true; \
	fi
	@git submodule init
	@git submodule update --remote --merge
	@echo "Submodules updated to latest main/master branch"

doc:
	./scripts/build-docs.sh

doc-preview: doc
	python3 -m http.server 8080 -d docs

# Java grammar for scripts/lib/java_openapi (via the ruby_tree_sitter gem), compiled from the C parser that a
# pinned tree-sitter-java release's source archive ships. Bump the version only when upstream Java syntax requires it.
TREE_SITTER_JAVA_VERSION = 0.23.5
TREE_SITTER_JAVA_SHA256 = cb199e0faae4b2c08425f88cbb51c1a9319612e7b96315a174a624db9bf3d9f0
TREE_SITTER_JAVA_URL = https://github.com/tree-sitter/tree-sitter-java/archive/refs/tags/v$(TREE_SITTER_JAVA_VERSION).tar.gz
TREE_SITTER_JAVA_SRC = .tmp/tree-sitter-java/$(TREE_SITTER_JAVA_VERSION)
TREE_SITTER_JAVA_LIB = .tmp/tree-sitter-java/libtree-sitter-java.$(if $(filter Darwin,$(shell uname -s)),dylib,so)

tree-sitter-java: $(TREE_SITTER_JAVA_LIB)

$(TREE_SITTER_JAVA_LIB): $(TREE_SITTER_JAVA_SRC)/src/parser.c
	cc -shared -fPIC -O2 -I $(TREE_SITTER_JAVA_SRC)/src $< -o $@

$(TREE_SITTER_JAVA_SRC)/src/parser.c:
	rm -rf $(TREE_SITTER_JAVA_SRC)
	mkdir -p $(TREE_SITTER_JAVA_SRC)
	curl -fsSL --retry 3 -o $(TREE_SITTER_JAVA_SRC).tar.gz $(TREE_SITTER_JAVA_URL)
	echo "$(TREE_SITTER_JAVA_SHA256)  $(TREE_SITTER_JAVA_SRC).tar.gz" | shasum -a 256 -c - \
		|| { rm -f $(TREE_SITTER_JAVA_SRC).tar.gz; exit 1; }
	tar -xzf $(TREE_SITTER_JAVA_SRC).tar.gz -C $(TREE_SITTER_JAVA_SRC) --strip-components 1 \
		tree-sitter-java-$(TREE_SITTER_JAVA_VERSION)/src
	rm -f $(TREE_SITTER_JAVA_SRC).tar.gz
	touch $@
