# Rooms — build, bundle, sign, run, test.
#   make run    build Rooms.app and (re)launch it
#   make test   run the RoomsCore tests
#   make release  universal (Apple silicon + Intel) Rooms.app, ad-hoc signed, zipped

APP_NAME := Rooms
BUNDLE   := build/$(APP_NAME).app
CONFIG   ?= release

# Use Xcode once its license is accepted; until then the Command Line Tools.
CLT := /Library/Developer/CommandLineTools
export DEVELOPER_DIR ?= $(shell xcrun xcodebuild -license check >/dev/null 2>&1 && xcode-select -p || echo $(CLT))

# Sign with the stable "Rooms Dev" certificate when it exists, so macOS keeps
# permissions across rebuilds. Falls back to ad-hoc signing.
SIGN_ID ?= $(shell security find-identity -p codesigning 2>/dev/null | awk '/"Rooms Dev"/ { print $$2; exit }' | grep . || echo -)

.PHONY: build app run test release clean

build:
	swift build -c $(CONFIG)

app: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$$(swift build -c $(CONFIG) --show-bin-path)/$(APP_NAME)" "$(BUNDLE)/Contents/MacOS/"
	cp Support/Info.plist "$(BUNDLE)/Contents/Info.plist"
	codesign --force --sign "$(SIGN_ID)" "$(BUNDLE)"
	@echo "Built $(BUNDLE) (signed: $(SIGN_ID))"

run: app
	-@pkill -x $(APP_NAME); sleep 0.3
	open "$(BUNDLE)"

test:
ifeq ($(DEVELOPER_DIR),$(CLT))
	swift test \
	  -Xswiftc -F -Xswiftc $(CLT)/Library/Developer/Frameworks \
	  -Xlinker -F -Xlinker $(CLT)/Library/Developer/Frameworks \
	  -Xlinker -rpath -Xlinker $(CLT)/Library/Developer/Frameworks \
	  -Xlinker -rpath -Xlinker $(CLT)/Library/Developer/usr/lib
else
	swift test
endif

# The downloadable build: one binary for Apple silicon and Intel, ad-hoc signed
# (not notarized: no Apple developer account), zipped for GitHub Releases.
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)
RELEASE_ZIP := build/Rooms-$(VERSION).zip

release:
	swift build -c release --arch arm64 --arch x86_64
	rm -rf "$(BUNDLE)" "$(RELEASE_ZIP)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$(APP_NAME)" "$(BUNDLE)/Contents/MacOS/"
	cp Support/Info.plist "$(BUNDLE)/Contents/Info.plist"
	# The compiler records where the source was built (for debuggers); strip that, so
	# the download doesn't carry this Mac's folder names, and refuse to ship if any remain.
	strip -S -x "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@if LC_ALL=C grep -a -q -e "$$HOME" -e "/Users/" "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"; then \
		echo "error: the release binary still contains a local path"; exit 1; fi
	# No extended attributes in the bundle or the ZIP: stored as ._ files, they end up
	# inside the app when it's unzipped with `unzip`, breaking its signature ("damaged").
	xattr -cr "$(BUNDLE)"
	codesign --force --sign - "$(BUNDLE)"
	ditto -c -k --norsrc --noextattr --noacl --keepParent "$(BUNDLE)" "$(RELEASE_ZIP)"
	@T=$$(mktemp -d) && unzip -q "$(RELEASE_ZIP)" -d "$$T" && codesign --verify --deep --strict "$$T/$(APP_NAME).app" \
		&& echo "ZIP unzips to a validly signed app"; S=$$?; rm -rf "$$T"; exit $$S
	@lipo -info "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@shasum -a 256 "$(RELEASE_ZIP)"

clean:
	rm -rf .build build
