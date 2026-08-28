#!/usr/bin/env bash
# Test: Named subagent registration and merge semantics
# Verifies the plugin's config hook registers the superpowers-* subagents,
# preserves user overrides field-by-field, and respects disabled agents.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Test: Named Subagent Registration ==="

source "$SCRIPT_DIR/setup.sh"
trap cleanup_test_env EXIT

node "$SCRIPT_DIR/test-named-agents-merge.mjs" "$SUPERPOWERS_PLUGIN_FILE"
echo "  [PASS] Named subagents registered, user overrides win, disabled agents respected"

echo ""
echo "=== All named subagent registration tests passed ==="
