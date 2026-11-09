.PHONY: build test test-raw run
build:
	./scripts/build.sh
test:
	SWIFT_EXEC="$$(xcrun --find swiftc)" CLANG_MODULE_CACHE_PATH="$(CURDIR)/.build/clang-cache" swift test --disable-sandbox --build-system native --scratch-path .build
test-raw:
	test -n "$$ISONIQUE_RAW_FIXTURES" && test -d "$$ISONIQUE_RAW_FIXTURES"
	SWIFT_EXEC="$$(xcrun --find swiftc)" CLANG_MODULE_CACHE_PATH="$(CURDIR)/.build/clang-cache" swift test --disable-sandbox --build-system native --scratch-path .build --configuration release --filter RawWorkflowTests
run: build
	open "build/Isonique.app"
