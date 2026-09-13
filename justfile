# Factory: CI for Factory itself. Tools come from mise.toml (run `mise install`).

# Recipes use bash features (process substitution); sh is dash on Debian-family runners.
set shell := ["bash", "-euo", "pipefail", "-c"]

_default:
    @just help

help:
    @echo ""
    @printf "\033[0;34m=== factory ===\033[0m\n"
    @printf "  %-12s %s\n" "fmt" "Format shell files with shfmt"
    @printf "  %-12s %s\n" "style" "Check formatting"
    @printf "  %-12s %s\n" "lint" "ShellCheck at all severities"
    @printf "  %-12s %s\n" "syntax" "bash -n on every script"
    @printf "  %-12s %s\n" "guard" "Apply guardrails.txt to our own source"
    @printf "  %-12s %s\n" "spell" "codespell"
    @printf "  %-12s %s\n" "test" "Bats tests"
    @printf "  %-12s %s\n" "ci" "All of the above, fail fast"
    @echo ""

fmt:
    shfmt -i 2 -ci -bn -w factory test/*.bats

style:
    @echo ""
    shfmt -i 2 -ci -bn -d factory test/*.bats
    @printf "\033[32m✓ style\033[0m\n"

lint:
    @echo ""
    shellcheck -S style -s bash factory
    shellcheck -S style -s bash -x -P SCRIPTDIR test/*.bats
    @printf "\033[32m✓ lint\033[0m\n"

syntax:
    @echo ""
    bash -n factory
    @printf "\033[32m✓ syntax\033[0m\n"

guard:
    @echo ""
    @if grep -nE -f <(grep -vE '^\s*(#|$)' guardrails.txt) factory justfile test/*.bats; then \
        printf "\033[31m✗ guard: our own source matches a forbidden pattern\033[0m\n" >&2; exit 1; fi
    @printf "\033[32m✓ guard\033[0m\n"

spell:
    @echo ""
    codespell factory guardrails.txt justfile README.md AGENTS.md CHANGELOG.md test
    @printf "\033[32m✓ spell\033[0m\n"

test:
    @echo ""
    bats test
    @printf "\033[32m✓ test\033[0m\n"

ci:
    #!/usr/bin/env bash
    set -euo pipefail
    just style
    just lint
    just syntax
    just guard
    just spell
    just test
    echo ""
    printf "\033[32m✓ ci\033[0m\n"
