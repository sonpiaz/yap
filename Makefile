.PHONY: generate build run clean

# Generate Xcode project from project.yml
generate:
	cd /Users/sonpiaz/yap && xcodegen generate

# Open in Xcode
open: generate
	open Yap.xcodeproj

# Build via xcodebuild
build: generate
	xcodebuild -project Yap.xcodeproj -scheme Yap -configuration Debug build

# Run the built app
run: build
	open build/Debug/Yap.app

# Clean
clean:
	rm -rf build DerivedData .build
	rm -rf Yap.xcodeproj
