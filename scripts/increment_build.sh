#!/bin/bash
# Auto-increment build number script
# This script increments the build number only in Debug builds

# Only increment in Debug configuration
if [ "${CONFIGURATION}" = "Debug" ]; then
    # Get the Info.plist path
    INFO_PLIST="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"
    
    # Get current build number
    buildNumber=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${INFO_PLIST}" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        # Increment build number
        buildNumber=$((buildNumber + 1))
        
        # Update build number
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "${INFO_PLIST}" 2>/dev/null
        
        echo "✅ Build number incremented to $buildNumber"
    else
        echo "⚠️ Could not read/update build number"
    fi
else
    echo "ℹ️ Skipping build number increment (Release build)"
fi

