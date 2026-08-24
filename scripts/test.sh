#!/bin/bash
# Run the test suite.
#
# Two Command Line Tools workarounds, both removable once full Xcode is installed:
#   1. swift-testing ships inside CLT but is not on SwiftPM's default search
#      path, so point at it explicitly.
#   2. _Testing_Foundation.framework ships without a .swiftmodule, so the
#      cross-import overlay cannot compile. Importing Foundation and Testing in
#      the same file fails without disabling cross-import overlays.
set -euo pipefail
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
exec swift test \
  -Xswiftc -F -Xswiftc "$FW" \
  -Xlinker -F -Xlinker "$FW" \
  -Xlinker -rpath -Xlinker "$FW" \
  -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  "$@"
