#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != Darwin ]; then
  echo 'IPA compilation requires macOS + Xcode 26 or newer. Use the included GitHub Actions workflow.' >&2
  exit 1
fi
command -v xcodegen >/dev/null || { echo 'Install XcodeGen: brew install xcodegen' >&2; exit 1; }
bash scripts/fetch-engine.sh
xcodebuild -version
xcodegen generate
mkdir -p build/tests
xcrun swiftc Locus/Support/MovementMath.swift Locus/Support/GoogleMapsLink.swift Tests/main.swift -o build/tests/movement
build/tests/movement
xcodebuild -project Locus.xcodeproj -scheme Locus -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  ARCHS=arm64 build
app_path=build/DerivedData/Build/Products/Release-iphoneos/KapiLocation.app
test -f "$app_path/KapiLocation"
mkdir -p build/package/Payload outputs
# Replace only this script's disposable packaging directory.
rm -rf build/package/Payload/KapiLocation.app
cp -R "$app_path" build/package/Payload/
rm -f outputs/KapiLocation-unsigned.ipa
(cd build/package && zip -qry ../../outputs/KapiLocation-unsigned.ipa Payload)
unzip -t outputs/KapiLocation-unsigned.ipa
shasum -a 256 outputs/KapiLocation-unsigned.ipa > outputs/SHA256SUMS.txt
echo 'Unsigned IPA ready. Install and sign locally with Sideloadly or AltStore Classic.'
