#!/bin/bash
#
# Reset CFBundleVerion and CFBundleShortVersionString after build

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion AUTOINCREMENT_FROM_GIT" "${PROJECT_DIR}/${INFOPLIST_FILE}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString AUTOINCREMENT_FROM_GIT" "${PROJECT_DIR}/${INFOPLIST_FILE}"
