# SENTRY — SOC · the verification gate (C11, `docs/ios/SPEC.md` §7).
#
#   make            the whole gate, in order, stopping at the first failure
#   make export     1 · content contract        make engine   2 · Swift parity
#   make app        3+4 · project + simulator   make shots    5 · screenshots
#   make guard      6 · the release guard       make clean    drop derived data
#
# Every target is idempotent and none of them commits anything. The gate is
# ordered cheapest-first on purpose: a content mistake fails in `export` after two
# seconds instead of eighteen minutes later in `guard`.
#
# Signing: simulator and CI builds pass CODE_SIGNING_ALLOWED=NO
# CODE_SIGNING_REQUIRED=NO on the command line (SPEC-ADDENDUM §6, amended
# 2026-09-05). `project.yml` itself keeps automatic signing so the founder's device
# run works — do not move these flags into the project.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

SIM ?= C2136147-45C8-42DD-8E3A-EDE974B97154
XCODEGEN ?= $(shell command -v xcodegen || echo /opt/homebrew/bin/xcodegen)
PROJECT := ios/SentrySOC.xcodeproj
SCHEME := SentrySOC
DERIVED := ios/.build
UNSIGNED := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
DEST := platform=iOS Simulator,id=$(SIM)

.DEFAULT_GOAL := all
.PHONY: all export contract engine project build test app shots guard verify clean help

## the whole gate, in SPEC §7 order
all: export contract engine app shots guard
	@printf '\n=== GATE GREEN — every step of SPEC §7 passed. ===\n'

# ── 1 · content contract (TypeScript) ────────────────────────────────────────

## regenerate the exported bundle and the seven fixtures
export:
	@printf '\n=== 1 · soc:export ===\n'
	npm run soc:export

## npm test (with the drift guard) · tsc · next build · the D1 merge-base diff
contract:
	@printf '\n=== 1 · npm test ===\n'
	npm test
	@printf '\n=== 1 · tsc --noEmit ===\n'
	npx tsc --noEmit -p tsconfig.json
	@printf '\n=== 1 · next build ===\n'
	npm run build
	@printf '\n=== 1 · D1 · protected web tree ===\n'
	bash ios/scripts/verify.sh d1

# ── 2 · engine parity — no simulator, no .xcodeproj ──────────────────────────

## swift test over SentryCore — the parity gate, 186 cases in 17 suites
engine:
	@printf '\n=== 2 · swift test ===\n'
	swift test --package-path ios/SentryCore

# ── 3+4 · project generation, simulator build, app-layer tests ───────────────

## regenerate the .xcodeproj from ios/project.yml (D24 — it is gitignored)
project:
	@printf '\n=== 3 · xcodegen generate ===\n'
	$(XCODEGEN) generate --spec ios/project.yml

build: project
	@printf '\n=== 4 · xcodebuild build (Debug, simulator, unsigned) ===\n'
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
	  -destination "$(DEST)" -derivedDataPath $(DERIVED) $(UNSIGNED)

test: build
	@printf '\n=== 4 · xcodebuild test (SentrySOCTests) ===\n'
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
	  -destination "$(DEST)" -derivedDataPath $(DERIVED) $(UNSIGNED)

## generate, build and test the app target
app: test

# ── 5 · screenshots ──────────────────────────────────────────────────────────

## 13 screens × 3 Dynamic Type sizes + the 375-pt pass → docs/screenshots/ios/gate/
shots: build
	@printf '\n=== 5 · screenshots ===\n'
	SENTRY_SKIP_BUILD=1 bash ios/scripts/shots.sh

# ── 6 · the release guard ────────────────────────────────────────────────────

## every condition of SPEC §7 step 6 — run this before any archive
guard:
	@printf '\n=== 6 · release guard ===\n'
	bash ios/scripts/verify.sh

## SPEC §7's older name for the guard
verify: guard

clean:
	rm -rf $(DERIVED) ios/.build/release $(PROJECT)

help:
	@grep -B1 -E '^[a-z]+:' $(MAKEFILE_LIST) | grep -A1 '^## ' \
	  | awk '/^## /{doc=substr($$0,4)} /^[a-z]+:/{split($$0,t,":"); printf "  make %-10s %s\n", t[1], doc}'
