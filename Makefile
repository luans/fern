PROJECT := Fern.xcodeproj
SCHEME := Fern
BUILD_DIR := build
APP := $(BUILD_DIR)/Build/Products/Debug/Fern.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(BUILD_DIR)
SOURCES := Fern FernTests FernUITests scripts

.PHONY: build run test ui-test format lint clean release version

build:
	$(XCODEBUILD) -configuration Debug build

run: build
	open $(APP)

test:
	$(XCODEBUILD) -only-testing:FernTests test

ui-test:
	$(XCODEBUILD) -only-testing:FernUITests test

format:
	xcrun swift-format format --in-place --recursive $(SOURCES)

lint:
	xcrun swift-format lint --strict --recursive $(SOURCES)

# Build de distribuição: Release, universal (Apple Silicon e Intel), compactado em zip, com o
# SHA-256 ao lado. Sem conta de desenvolvedor, o app sai com assinatura local (ver README ›
# Distribuição).
#
# A versão padrão vem de MARKETING_VERSION no projeto. Para outra, sem editar o projeto:
#   make release VERSION=0.7.0 BUILD_NUMBER=42
# Um sufixo (0.7.0-beta.1) vai só no nome do zip; o app recebe a parte numérica (0.7.0).
RELEASE_APP := $(BUILD_DIR)/Build/Products/Release/Fern.app
PROJECT_VERSION := $(shell sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' $(PROJECT)/project.pbxproj | head -1)
VERSION ?= $(PROJECT_VERSION)
BUILD_NUMBER ?=
APP_VERSION := $(firstword $(subst -, ,$(VERSION)))
ZIP := Fern-$(VERSION).zip
RELEASE_FLAGS := MARKETING_VERSION=$(APP_VERSION) $(if $(BUILD_NUMBER),CURRENT_PROJECT_VERSION=$(BUILD_NUMBER))

release:
	$(XCODEBUILD) -configuration Release $(RELEASE_FLAGS) clean build
	rm -f $(BUILD_DIR)/$(ZIP) $(BUILD_DIR)/$(ZIP).sha256
	ditto -c -k --keepParent $(RELEASE_APP) $(BUILD_DIR)/$(ZIP)
	cd $(BUILD_DIR) && shasum -a 256 $(ZIP) > $(ZIP).sha256
	@echo "Pronto: $(BUILD_DIR)/$(ZIP)"

# Mostra a versão do projeto (MARKETING_VERSION).
version:
	@echo $(PROJECT_VERSION)

clean:
	rm -rf $(BUILD_DIR)
