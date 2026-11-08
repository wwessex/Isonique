.PHONY: build test run
build:
	./scripts/build.sh
test:
	SWIFT_EXEC="$$(xcrun --find swiftc)" CLANG_MODULE_CACHE_PATH="$(CURDIR)/.build/clang-cache" swift test --disable-sandbox --build-system native --scratch-path .build
run: build
	open "build/Isonique.app"
