.PHONY: setup deps clean clean-all clean-vendors generate build format lint install-hooks

# First-time project setup: submodules + Xcode project generation + SPM resolve + git hooks.
# Run this after `make clean-all` (or on a fresh clone) to get a fully working build.
setup: install-hooks
	@echo "Initializing and updating git submodules..."
	git submodule update --init --recursive
	@echo "Generating Xcode project..."
	xcodegen generate
	@echo "Resolving Swift Package Manager dependencies..."
	xcodebuild -project Logue.xcodeproj -scheme Logue -resolvePackageDependencies \
		-clonedSourcePackagesDirPath ~/Library/Developer/Xcode/DerivedData/Logue-SPM
	@echo "Setup complete. Open Logue.xcodeproj to get started."

# Resolve / refresh Swift Package Manager dependencies without touching submodules or git hooks.
# Use this when packages in project.yml have changed (added, removed, or version-bumped),
# or after `make clean-all` wiped DerivedData and you want to pre-fetch packages without
# kicking off a full build. Safe to run repeatedly — SPM is idempotent.
deps: generate
	@echo "Resolving Swift Package Manager dependencies..."
	@echo "  - mlx-swift-lm (MLXLLM, MLXLMCommon)"
	@echo "  - swift-transformers-mlx (MLXLMTransformers)"
	@echo "  - swift-hf-api-mlx (MLXLMHFAPI)"
	@echo "  - FluidAudio, Sparkle, Textual, LangGraph, swift-markdown"
	xcodebuild -project Logue.xcodeproj -scheme Logue -resolvePackageDependencies \
		-clonedSourcePackagesDirPath ~/Library/Developer/Xcode/DerivedData/Logue-SPM
	@echo "Dependencies resolved."

# Install git pre-commit and pre-push hooks
install-hooks:
	@echo "Installing git hooks..."
	@printf '#!/bin/bash\n\
# Pre-commit hook: lint staged Swift files\n\
set -e\n\
\n\
STAGED=$$(git diff --cached --name-only --diff-filter=ACM -- "*.swift")\n\
if [ -z "$$STAGED" ]; then\n\
  exit 0\n\
fi\n\
\n\
echo "Pre-commit: checking staged Swift files..."\n\
\n\
# SwiftFormat lint\n\
echo "$$STAGED" | xargs swiftformat --lint --quiet\n\
\n\
# SwiftLint lint (strict: warnings are errors)\n\
echo "$$STAGED" | xargs swiftlint lint --strict --quiet\n\
\n\
echo "Pre-commit: all checks passed."\n' > .git/hooks/pre-commit
	@printf '#!/bin/bash\n\
# Pre-push hook: full repo lint check\n\
set -e\n\
\n\
echo "Pre-push: running full lint check..."\n\
\n\
swiftformat --lint Logue/\n\
swiftlint lint --strict Logue/\n\
\n\
echo "Pre-push: all checks passed."\n' > .git/hooks/pre-push
	@chmod +x .git/hooks/pre-commit .git/hooks/pre-push
	@echo "Git hooks installed (pre-commit + pre-push)."

# Reset app data (preferences, keychain, meetings, docs) but keep downloaded models
clean:
	@echo "Stopping Logue if running..."
	-@pkill -f "Logue.app" 2>/dev/null; sleep 1; true
	@echo "Resetting Logue app data (keeping models)..."
	# UserDefaults — flush cfprefsd cache then delete plists
	-@defaults delete com.bitwize.logue 2>/dev/null; true
	-@rm -f ~/Library/Preferences/com.bitwize.logue.plist 2>/dev/null; true
	-@rm -f ~/Library/Containers/com.bitwize.logue/Data/Library/Preferences/com.bitwize.logue.plist 2>/dev/null; true
	# Keychain entries (AES-256-GCM at-rest encryption key + migration flag)
	-@security delete-generic-password -s "com.bitwize.logue" -a "encryption_key_v1" 2>/dev/null; true
	-@security delete-generic-password -s "com.bitwize.logue" -a "encryption_migration_complete_v1" 2>/dev/null; true
	# App data (documents, meetings, datastores)
	-@rm -rf ~/Library/Application\ Support/Logue/ 2>/dev/null; true
	-@rm -rf ~/Library/Application\ Support/com.bitwize.logue/ 2>/dev/null; true
	-@rm -rf ~/Library/Containers/com.bitwize.logue/Data/Library/Application\ Support/ 2>/dev/null; true
	# Caches
	-@rm -rf ~/Library/Caches/com.bitwize.logue/ 2>/dev/null; true
	-@rm -rf ~/Library/Containers/com.bitwize.logue/Data/Library/Caches/ 2>/dev/null; true
	# HTTP storage & cookies
	-@rm -rf ~/Library/HTTPStorages/com.bitwize.logue/ 2>/dev/null; true
	-@rm -rf ~/Library/HTTPStorages/com.bitwize.logue.binarycookies 2>/dev/null; true
	-@rm -rf ~/Library/Cookies/com.bitwize.logue.binarycookies 2>/dev/null; true
	# Saved application state
	-@rm -rf ~/Library/Saved\ Application\ State/com.bitwize.logue.savedState/ 2>/dev/null; true
	# WebKit storage
	-@rm -rf ~/Library/WebKit/com.bitwize.logue/ 2>/dev/null; true
	# TCC permissions (microphone, speech, calendar, accessibility)
	-@tccutil reset Microphone com.bitwize.logue 2>/dev/null; true
	-@tccutil reset SpeechRecognition com.bitwize.logue 2>/dev/null; true
	-@tccutil reset Calendar com.bitwize.logue 2>/dev/null; true
	-@tccutil reset Accessibility com.bitwize.logue 2>/dev/null; true
	@echo "Done. Models preserved. Next launch will show onboarding."

# Nuke everything including downloaded models (multi-GB) and build artifacts
clean-all: clean
	@echo "Removing downloaded MLX LLM models (HuggingFace hub cache)..."
	# New mlx-swift-lm path: swift-hf-api-mlx HubClient.default uses the standard
	# HuggingFace hub cache layout at ~/.cache/huggingface/hub/models--<org>--<name>/.
	# Removes both `hub/` (snapshots + blobs) and `xet/` (content-addressed backend).
	# Note: this is shared with any other HF tooling (Python transformers, etc.).
	-@rm -rf ~/.cache/huggingface/ 2>/dev/null; true
	@echo "Removing legacy LocalLLMClient model cache (pre-mlx-swift-lm migration)..."
	# Legacy path from before commit 6914f27 (refactor to mlx-swift-lm). Safe to remove
	# for any users still carrying ~7GB of stale weights from the old SDK.
	-@rm -rf ~/.localllmclient/ 2>/dev/null; true
	@echo "Removing FluidAudio diarization models..."
	# Sortformer + speaker-diarization weights downloaded by FluidAudio at runtime.
	-@rm -rf ~/Library/Application\ Support/FluidAudio/ 2>/dev/null; true
	@echo "Removing DerivedData..."
	-@rm -rf ~/Library/Developer/Xcode/DerivedData/Logue-* 2>/dev/null; true
	@echo "Removing SPM package cache..."
	-@rm -rf ~/Library/Caches/org.swift.swiftpm/ 2>/dev/null; true
	-@rm -f Logue.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved 2>/dev/null; true
	@echo "Done. All data wiped. Run 'make setup' to rebuild."

# Regenerate Xcode project from project.yml
generate:
	xcodegen generate

# Format Swift files with SwiftFormat
format:
	swiftformat Logue/

# Lint Swift files with SwiftLint
lint:
	swiftlint lint Logue/

# Build the project (no code signing for local/CI builds)
build: generate
	xcodebuild -project Logue.xcodeproj -scheme Logue -configuration Debug build \
		CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
