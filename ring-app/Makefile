DERIVED_DATA ?= /tmp/ring-derived
SCHEME ?= Ring
CONFIG ?= Debug
BUILD_APP := $(DERIVED_DATA)/Build/Products/$(CONFIG)/Ring.app
APP_PATH ?= /Applications/Ring.app

.PHONY: generate build-debug run install-app restart-app

generate:
	xcodegen generate

build-debug: generate
	xcodebuild -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath $(DERIVED_DATA) build

run: build-debug
	open $(BUILD_APP)

install-app: build-debug
	@echo "Installing $(BUILD_APP) -> $(APP_PATH)"
	/usr/bin/ditto $(BUILD_APP) $(APP_PATH)
	@echo "Installed Ring.app to $(APP_PATH)"

restart-app: install-app
	pkill -x Ring || true
	open $(APP_PATH)
