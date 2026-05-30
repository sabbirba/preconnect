#!/usr/bin/env bash
set -euo pipefail

# Trigger the GitHub Actions workflow that builds & publishes the DevContainer image.
# Requires GitHub CLI (gh) authenticated with sufficient privileges.
# Usage:
#   gh auth login
#   ./scripts/trigger_publish.sh

WORKFLOW_ID="publish-devcontainer.yml"
REPO="${GITHUB_REPO:-sabbirba/preconnect}"

echo "Triggering workflow ${WORKFLOW_ID} on repo ${REPO}"
gh workflow run "$WORKFLOW_ID" --repo "$REPO"
echo "Workflow dispatched. Check Actions tab for progress."
