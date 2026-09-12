#!/usr/bin/env sh
set -eu

# Google Play: one upload artifact; Play serves ABI-specific APKs.
flutter build appbundle --release

# Direct distribution: one APK per ABI, not a universal multi-ABI APK.
flutter build apk --release --split-per-abi
