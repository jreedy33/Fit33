#!/bin/bash
# Bump version for Fit33 app
# Usage: ./bump_version.sh 1.11.1 1
# Or just: ./bump_version.sh (auto-increments patch version)

set -e

XCODEPROJ="Fit33.xcodeproj/project.pbxproj"

if [ ! -f "$XCODEPROJ" ]; then
    echo "❌ Error: $XCODEPROJ not found"
    exit 1
fi

# Get current versions
CURRENT_MARKETING=$(grep -m1 "MARKETING_VERSION = " "$XCODEPROJ" | sed 's/.*MARKETING_VERSION = \(.*\);/\1/')
CURRENT_BUILD=$(grep -m1 "CURRENT_PROJECT_VERSION = " "$XCODEPROJ" | sed 's/.*CURRENT_PROJECT_VERSION = \(.*\);/\1/')

echo "📱 Current version: $CURRENT_MARKETING (build $CURRENT_BUILD)"

# If version provided, use it; otherwise auto-increment
if [ -n "$1" ]; then
    NEW_MARKETING="$1"
    NEW_BUILD="${2:-1}"
else
    # Auto-increment patch version (1.11.1 -> 1.11.2)
    IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_MARKETING"
    MAJOR="${VERSION_PARTS[0]}"
    MINOR="${VERSION_PARTS[1]}"
    PATCH="${VERSION_PARTS[2]}"
    NEW_PATCH=$((PATCH + 1))
    NEW_MARKETING="$MAJOR.$MINOR.$NEW_PATCH"
    NEW_BUILD="$NEW_PATCH"
fi

echo "⬆️  Bumping to: $NEW_MARKETING (build $NEW_BUILD)"

# Update project file
sed -i '' "s/MARKETING_VERSION = .*/MARKETING_VERSION = $NEW_MARKETING;/g" "$XCODEPROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$XCODEPROJ"

echo "✅ Version updated to $NEW_MARKETING (build $NEW_BUILD)"
echo ""
echo "Next steps:"
echo "  1. git add Fit33.xcodeproj/project.pbxproj"
echo "  2. git commit -m 'Bump version to v$NEW_MARKETING'"
echo "  3. Archive and upload to App Store Connect"
