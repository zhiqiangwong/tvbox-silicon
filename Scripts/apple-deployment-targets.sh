#!/bin/bash
# Centralized deployment targets for Apple platforms across Yingxia build scripts
case ":$PATH:" in
  *:/opt/homebrew/bin:*) ;;
  *) [ -d /opt/homebrew/bin ] && export PATH="/opt/homebrew/bin:$PATH" ;;
esac
if [ -z "${JAVA_HOME:-}" ] && [ -d "$HOME/.sdkman/candidates/java/current" ]; then
  export JAVA_HOME="$HOME/.sdkman/candidates/java/current"
  export PATH="$JAVA_HOME/bin:$PATH"
fi
IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-${YINGXIA_IOS_DEPLOYMENT_TARGET:-16.0}}"
TVOS_DEPLOYMENT_TARGET="${TVOS_DEPLOYMENT_TARGET:-${YINGXIA_TVOS_DEPLOYMENT_TARGET:-17.0}}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-${YINGXIA_MACOS_DEPLOYMENT_TARGET:-14.0}}"
export IOS_DEPLOYMENT_TARGET
export MACOS_DEPLOYMENT_TARGET
export YINGXIA_IOS_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET"
export YINGXIA_TVOS_DEPLOYMENT_TARGET="$TVOS_DEPLOYMENT_TARGET"
export YINGXIA_MACOS_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"
# Un-export TVOS_DEPLOYMENT_TARGET so Apple clang does not treat host Mac builds as tvOS targets
export -n TVOS_DEPLOYMENT_TARGET 2>/dev/null || true
