#!/bin/bash
#
# GitHub Actions File Change Checker
#
# This script checks if files in a PR or push match a given pattern.
# It uses the GitHub CLI to fetch changed files without requiring checkout.
#
# Usage: check-file-changes.sh "regex_pattern"
# Example: check-file-changes.sh "^(proto/|server/golang/)"
#

set -e

# Validate required environment variables
if [ -z "$GITHUB_OUTPUT" ]; then
  echo "❌ Error: GITHUB_OUTPUT environment variable not set"
  exit 1
fi

if [ -z "$GITHUB_EVENT_NAME" ]; then
  echo "❌ Error: GITHUB_EVENT_NAME environment variable not set"
  exit 1
fi

# Get pattern from first argument
PATTERN="${1:-.*}"
echo "🔍 Checking for files matching pattern: $PATTERN"
echo ""

# Get list of changed files based on event type
if [ "$GITHUB_EVENT_NAME" = "pull_request" ]; then
  echo "📥 Detected pull_request event"

  if [ -z "$GITHUB_REPOSITORY" ] || [ -z "$GITHUB_PR_NUMBER" ]; then
    echo "❌ Error: Missing GITHUB_REPOSITORY or GITHUB_PR_NUMBER"
    exit 1
  fi

  echo "Fetching files from PR #$GITHUB_PR_NUMBER..."
  FILES=$(gh api --paginate "repos/$GITHUB_REPOSITORY/pulls/$GITHUB_PR_NUMBER/files" \
    --jq '.[].filename' 2>&1)

  if [ $? -ne 0 ]; then
    echo "❌ Error fetching PR files:"
    echo "$FILES"
    exit 1
  fi

elif [ "$GITHUB_EVENT_NAME" = "push" ]; then
  echo "📤 Detected push event"

  if [ -z "$GITHUB_REPOSITORY" ] || [ -z "$GITHUB_EVENT_BEFORE" ] || [ -z "$GITHUB_EVENT_AFTER"]; then
    echo "❌ Error: Missing GITHUB_REPOSITORY, GITHUB_EVENT_BEFORE, or GITHUB_EVENT_AFTER"
    exit 1
  fi

  echo "Fetching files from commits $GITHUB_EVENT_BEFORE..$GITHUB_EVENT_AFTER..."
  FILES=$(gh api "repos/$GITHUB_REPOSITORY/compare/$GITHUB_EVENT_BEFORE...$GITHUB_EVENT_AFTER" \
    --jq '.files[].filename' 2>&1)

  if [ $? -ne 0 ]; then
    echo "❌ Error fetching commit comparison:"
    echo "$FILES"
    exit 1
  fi

else
  echo "❌ Error: Unsupported event type: $GITHUB_EVENT_NAME"
  echo "Supported events: pull_request, push"
  exit 1
fi

# Convert to space-separated list for processing
FILES_LIST=$(echo "$FILES" | tr '\n' ' ')
FILE_COUNT=$(echo "$FILES" | wc -l | tr -d ' ')

echo "Found $FILE_COUNT changed file(s)"
echo ""

# Check if any files match the pattern
MATCHED="false"
MATCHED_FILES=""

for file in $FILES_LIST; do
  if [ -n "$file" ] && echo "$file" | grep -qE "$PATTERN"; then
    echo "  ✅ $file"
    MATCHED="true"
    MATCHED_FILES="${MATCHED_FILES}${file}"$'\n'
  fi
done

echo ""

# Set GitHub Actions output
if [ "$MATCHED" = "true" ]; then
  echo "✅ Files match pattern - build should run"
  echo "changed=true" >> "$GITHUB_OUTPUT"
else
  echo "⏭️  No files match pattern - build can be skipped"
  echo "changed=false" >> "$GITHUB_OUTPUT"
fi

exit 0
