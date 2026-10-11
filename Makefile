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
	@# vendor/tree-sitter-java is deliberately excluded: it stays pinned to the grammar commit recorded in the repo.
	@git submodule update --remote --merge -- vendor/java-slack-sdk vendor/slack-api-ref
	@echo "Submodules updated to latest main/master branch"

doc:
	./scripts/build-docs.sh

doc-preview: doc
	python3 -m http.server 8080 -d docs

# Grammar shared library used by scripts/lib/java_openapi (via the ruby_tree_sitter gem).
TREE_SITTER_JAVA_LIB = .tmp/tree-sitter-java/libtree-sitter-java.$(if $(filter Darwin,$(shell uname -s)),dylib,so)

tree-sitter-java: $(TREE_SITTER_JAVA_LIB)

$(TREE_SITTER_JAVA_LIB): vendor/tree-sitter-java/src/parser.c
	mkdir -p $(dir $@)
	cc -shared -fPIC -O2 -I vendor/tree-sitter-java/src vendor/tree-sitter-java/src/parser.c -o $@
