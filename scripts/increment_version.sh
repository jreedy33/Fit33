#!/bin/bash

# Auto-increment the patch version (1.5.3 → 1.5.4)
# This script updates MARKETING_VERSION in project.pbxproj

PROJECT_FILE="${PROJECT_DIR}/GoFit.xcodeproj/project.pbxproj"

# Get current marketing version (find the main app's version, not extensions)
CURRENT_VERSION=$(grep -m1 "MARKETING_VERSION = 1\." "$PROJECT_FILE" | sed 's/.*MARKETING_VERSION = \([0-9.]*\);/\1/')

if [ -z "$CURRENT_VERSION" ]; then
    echo "Could not find current version"
    exit 0
fi

# Split version into components
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Increment patch version
NEW_PATCH=$((PATCH + 1))
NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}"

echo "Incrementing version: $CURRENT_VERSION → $NEW_VERSION"

# Update the project file (only update the main app version, not extensions)
sed -i '' "s/MARKETING_VERSION = ${CURRENT_VERSION};/MARKETING_VERSION = ${NEW_VERSION};/" "$PROJECT_FILE"

echo "Version updated to $NEW_VERSION"

