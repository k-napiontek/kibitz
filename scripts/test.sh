#!/bin/bash
# Run the test suite.
#
# Prefers Xcode when it is installed, because swift-testing needs it. Setting
# DEVELOPER_DIR avoids requiring `sudo xcode-select -s`, which is worth doing
# once but is not a prerequisite for building this project.
#
# Falls back to Command Line Tools, where swift-testing ships but is neither on
# SwiftPM's default search path nor able to cross-import Foundation, since
# _Testing_Foundation.framework has no .swiftmodule there.
set -euo pipefail

XCODE=/Applications/Xcode.app/Contents/Developer

if [ -d "$XCODE" ]; then
    export DEVELOPER_DIR="$XCODE"
    exec swift test "$@"
fi

FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
exec swift test \
  -Xswiftc -F -Xswiftc "$FW" \
  -Xlinker -F -Xlinker "$FW" \
  -Xlinker -rpath -Xlinker "$FW" \
  -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  "$@"
