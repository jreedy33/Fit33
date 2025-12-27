#!/bin/bash

# Manual version bump script
# Run from project root: ./scripts/bump_version.sh

cd "$(dirname "$0")/.."
PROJECT_FILE="./GoFit.xcodeproj/project.pbxproj"

# Get current marketing version (look for 1.5.x pattern - the main app)
CURRENT_VERSION=$(grep "MARKETING_VERSION = 1\.5\." "$PROJECT_FILE" | head -1 | sed 's/.*MARKETING_VERSION = \([0-9.]*\);/\1/')

if [ -z "$CURRENT_VERSION" ]; then
    echo "❌ Could not find current version (looking for 1.5.x)"
    exit 1
fi

# Split version into components
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Increment patch version
NEW_PATCH=$((PATCH + 1))
NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}"

echo "📱 Current version: $CURRENT_VERSION"
echo "🚀 New version: $NEW_VERSION"
echo ""

# Update the project file
sed -i '' "s/MARKETING_VERSION = ${CURRENT_VERSION};/MARKETING_VERSION = ${NEW_VERSION};/g" "$PROJECT_FILE"
echo "✅ Version updated to $NEW_VERSION"

# Commit the change
git add "$PROJECT_FILE"
git commit -m "Bump version to $NEW_VERSION"
echo "✅ Committed version bump"
