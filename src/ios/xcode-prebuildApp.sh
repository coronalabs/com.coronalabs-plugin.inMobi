#!/bin/bash
#
# Auto update CFBundleVersion and CFBundleShortVersionString from git.

# see if git versioning info is already available 
if [ -z "$versionString" ]; then
    . ${PROJECT_DIR}/xcode-getVersionFromGit.sh
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $bundleVersion" "${PROJECT_DIR}/${INFOPLIST_FILE}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $versionString" "${PROJECT_DIR}/${INFOPLIST_FILE}"