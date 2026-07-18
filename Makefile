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

format:
	swift package plugin --allow-writing-to-package-directory swiftformat -- Sources DemoApps/Examples Tests

format-generated:
	swift package plugin --allow-writing-to-package-directory swiftformat -- Sources/SlackClient/WebAPI/Generated Sources/SlackApp/Events/Generated Sources/SlackModels/Generated

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
