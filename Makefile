.PHONY: build build-debug test

build:
	zig build -Doptimize=fast

build-debug:
	zig build

test:
	zig build test
