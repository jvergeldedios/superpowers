#!/usr/bin/env bash
# Test: Named subagent dispatch
# Verifies the plugin registers the superpowers-* named subagents and that
# OpenCode's task tool can dispatch to them by name.
# NOTE: Requires OpenCode to be installed and configured.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENCODE_TEST_TIMEOUT_SECONDS="${OPENCODE_TEST_TIMEOUT_SECONDS:-120}"

echo "=== Test: Named Subagent Dispatch ==="

source "$SCRIPT_DIR/setup.sh"
trap cleanup_test_env EXIT

# Check if opencode is available
if ! command -v opencode &> /dev/null; then
    echo "  [SKIP] OpenCode not installed - skipping integration test"
    echo "  To run this test, install OpenCode: https://opencode.ai"
    exit 0
fi

run_opencode() {
    local result_var="$1"
    local dir="$2"
    local prompt="$3"
    local command_output
    local exit_code

    set +e
    command_output=$(cd "$dir" && timeout "${OPENCODE_TEST_TIMEOUT_SECONDS}s" opencode run --print-logs --format json "$prompt" 2>&1)
    exit_code=$?
    set -e

    if [ $exit_code -eq 124 ]; then
        echo "  [FAIL] OpenCode timed out after ${OPENCODE_TEST_TIMEOUT_SECONDS}s"
        exit 1
    fi

    if [ $exit_code -ne 0 ]; then
        echo "  [FAIL] OpenCode returned non-zero exit code: $exit_code"
        echo "  Output was:"
        awk 'NR <= 80 { print }' <<<"$command_output"
        exit 1
    fi

    printf -v "$result_var" '%s' "$command_output"
}

assert_contains() {
    local output="$1"
    local needle="$2"
    local message="$3"

    if [[ "$output" == *"$needle"* ]]; then
        echo "  [PASS] $message"
    else
        echo "  [FAIL] $message"
        echo "  Expected to find: $needle"
        echo "  Output was:"
        awk 'NR <= 80 { print }' <<<"$output"
        exit 1
    fi
}

echo "Test 1: Dispatching to the named explorer subagent..."
run_opencode output "$TEST_HOME/test-project" "Call the task tool with subagent_type \"superpowers-explorer\" and prompt \"Reply with exactly: EXPLORER_MARKER_24680\". Then print the marker."
assert_contains "$output" '"subagent_type":"superpowers-explorer"' "task tool dispatched to superpowers-explorer"
assert_contains "$output" "EXPLORER_MARKER_24680" "named explorer subagent executed and reported"

echo ""
echo "=== All named subagent dispatch tests passed ==="
